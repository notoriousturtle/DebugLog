//
//  DebugLog.swift
//  By notorious_turtle
//
//  A simple debug logging solution designed for iOS, and WatchOS written in Swift 3.
//
//  - Logs to a text file, "debug.log" in the app's Documents directory
//  - Log an entry with a tag prefix, e.g.
//      DebugLog.log(tag: "main", content: "bbbbbbbb")
//    Outputs (to log and console):
//      2016-10-05 16:55:07.920 | main | bbbbbbbb
//    If you want to suppress the message to console do:
//      debug.log(tag: "main", content: "bbbbbbbb", echo: false)
//  - If you want to print to console only, and not the log (generally for formatting purposes), use:
//      debug.pp(tag: "main", content: "bbbbbbbb")
//
//  - Checks if file size is greater than 500KB, if so, it uploads it, then wipes it
//  - It doesn't prompt for auth, even when it needs to. The log will be removed.
//    This is done to prevent any negative effects on the user experience
//
//  SAMPLE IMPLEMENTATION:
/*
    The below code will enable debugging, setup a new session, remove the log, log something, then upload it, and clear it again
    The most basic implementation could be:
    override func viewDidLoad() {
        var debug = DebugLog() //enable debugging
        debug.enableLogging()
 
        debug = DebugLog(setup: true) //setup new session
        debug.log(tag: "ViewController", content: "viewDidLoad called")
        debug.sendLog()
    }

    debug.sendLog() to send asynchoronously
    debug.sendLogSynchronously() to send synchoronously
 
    I have it setup so whenever applicationWillResignActive is called, it uploads the log, then when applicationDidBecomeActive
    is called I create a new debugging session again. I do this like so:
 
    func applicationWillResignActive(_ application: UIApplication) {
        debug.log(tag: "AppDelegate", content: "applicationWillResignActive - app went from active to inactive")
        debug.sendLogSynchronously()
    }
     
    func applicationDidBecomeActive(_ application: UIApplication) {
        debug.log(tag: "AppDelegate", content: "applicationDidBecomeActive - app became active")
 
        debug.enableLogging() //enable logging
        debug.empty() //remove old log (if any)
 
        debug = DebugLog(setup: true)
 
        //for the log file, dont print to console
        debug.log(tag: "AppDelegate", content: "applicationDidBecomeActive - app became active", echo: false)
    }
 
    The log is sent in a POST request like so:
    POST /api/error-logs/add HTTP/1.1
    Host: domain
    Accept: application/json
    Content-Type: application/json; charset=utf-8
    X-Requested-With: XMLHttpRequest
    Cookie: CAKEPHP=1234567890
    Content-Length: 103

    { "DebugLog": [ "2016-10-05 16:55:07.920 | main | bbbbbbbb", "2016-10-05 16:55:07.920 | main | bbbbbbbb" ] }
 
    On response, server should return JSON response like so:
    { "success": true }
    */
//
//  Created by notorious_turtle on 5/10/16.
//  Copyright © 2016 notorious_turtle. All rights reserved.
//

import UIKit

class DebugLog: NSObject, URLSessionDelegate {
    let path = NSHomeDirectory()+"/Documents/debug.log"
    let fileSizeLimit: Double = 500
    
    //define your server here, e.g. server = "https://example.com"
    //in my case, mine is defined via a Singleton variable
    let server = GlobalVariables.sharedManager.server
    
    var loggingEnabled = false
    var uploadingLog = false
    var fallbackBuffer = [String]()
    var fallbackBufferCounter = 0
    
    init(setup: Bool? = false) {
        super.init()
        
        loggingEnabled = isLoggingEnabled() //always check status
        
        if let initialise = setup {
            if initialise {
                self.log(tag: "DebugLog", content: "New debugging instance created")
                self.pp(tag: "DebugLog", content: "Logging enabled: *** \(loggingEnabled) ***")
            }
        }
    }
    
    //enable logging
    func enableLogging() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "debugLogging")
    }
    
    //check logging is enabled
    func isLoggingEnabled() -> Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: "debugLogging")
    }
    
    //disable logging
    func disableLogging() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "debugLogging")
    }
    
    private func getTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
    
    private func getTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
    
    //pretty print to console only
    func pp(tag: String, content: String) {
        let formatted = self.getTime()+"|"+tag+"|"+content
        print(formatted)
    }
    
    //log entry, with a tag.
    func log(tag: String, content: String, echo: Bool? = true) {
        let time = getTime()
        let now = getTimestamp()
        
        //create log string
        var contentToAppend = "|"+tag+"|"+content
        if let echoEntry = echo {
            if echoEntry {
                print(time+contentToAppend)
            }
        }
        
        contentToAppend = now+contentToAppend+"\n"
        
        //check if logging is enabled, else return
        if loggingEnabled == false {
            return
        }
        
        //check log file size
        //if greater than fileSizeLimit, send it, wipe it and start over
        if self.getLogSize() > fileSizeLimit {
            if uploadingLog { //already uploading, so dont send this log off yet
                fallbackBufferCounter = fallbackBufferCounter + 1
                fallbackBuffer.append(contentToAppend)
                //self.pp(tag: "DebugLog", content: "Using fallbackBuffer")
                
                if fallbackBufferCounter > 2000 {
                    //delete it, so it doesn't consume memory
                    //these logs disappear
                    fallbackBuffer.removeAll()
                    fallbackBufferCounter = 0
                    self.pp(tag: "DebugLog", content: "FallbackBuffer full. Emptied it.")
                }
            }
            else {
                self.sendLog()
            }
        }
        
        //check if file exists
        if let fileHandle = FileHandle(forWritingAtPath: path) {
            //append to file
            fileHandle.seekToEndOfFile()
            fileHandle.write(contentToAppend.data(using: String.Encoding.utf8)!)
        }
        else {
            //create new file
            do {
                try contentToAppend.write(toFile: path, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                self.pp(tag: "DebugLog", content: "Error creating \(path)")
            }
        }
    }
    
    //read debug file, return string array
    func read() -> [String] {
        var entries = [String]()
        
        do {
            let data = try String(contentsOfFile: path, encoding: .utf8)
            entries = data.components(separatedBy: .newlines)
            entries.removeLast() //an empty line
        }
        catch {
            self.pp(tag: "DebugLog", content: "Could not read debug file. "+error.localizedDescription)
        }
        
        return entries
    }
    
    //delete/empty debug file
    func empty() {
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: path) == false {
            self.pp(tag: "DebugLog", content: "Path does not exist, cannot remove log")
            return
        }
        
        //file exists, attempt to remove it
        do {
            try fileManager.removeItem(atPath: path)
            self.pp(tag: "DebugLog", content: "Removed log file")
        }
        catch {
            self.pp(tag: "DebugLog", content: "Could not delete debug file. "+error.localizedDescription)
        }
    }
    
    //get size of log file
    private func getLogSize() -> Double {
        var size: Double = 0
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: path) == false {
            return size
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            if let bytes = attributes[FileAttributeKey.size] as? NSNumber {
                let kb = bytes.doubleValue / 1024
                size = kb
            }
        }
        catch {
            self.pp(tag: "DebugLog", content: "Could not get attributes of debug file. "+error.localizedDescription)
        }
        
        return size
    }
    
    // MARK: - NetworkRelated
    
    func sendLog() {
        let url = URL(string: server+"/api/error-logs/add")
        var urlRequest = URLRequest(url: url!)
        urlRequest.httpMethod = "POST"
        var success = false
        
        uploadingLog = true
        
        //load log into memory
        var cache = self.read()
        
        //if any data is cached, upload that as well
        if fallbackBufferCounter > 0 {
            cache.append(contentsOf: fallbackBuffer)
            fallbackBufferCounter = 0
        }
        
        self.pp(tag: "DebugLog", content: "Sending debug log")
        
        let body: NSDictionary = ["log": cache]
        let jsonData: Data
        
        do {
            jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
            urlRequest.httpBody = jsonData
        }
        catch {
            self.pp(tag: "DebugLog", content: "Error, cannot create JSON debug log")
        }
        
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        
        let session = URLSession.shared
        let task = session.dataTask(with: urlRequest, completionHandler: {
            (data, response, error) in
            guard error == nil else {
                self.pp(tag: "DebugLog", content: "Error, calling POST on /api/error-logs/add")
                self.pp(tag: "DebugLog", content: error!.localizedDescription)
                return
            }
            
            guard let responseJson = data else {
                self.pp(tag: "DebugLog", content: "Error, did not recieve any data")
                return
            }
            
            let responseCode = response as! HTTPURLResponse
            if responseCode.statusCode == 200 {
                if let resultJSON = JsonHelper.parseJSON(data: responseJson) {
                    guard let successObj = resultJSON["success"] as? Bool else {
                        self.pp(tag: "DebugLog", content: "Could not get success as Bool from json");
                        return
                    }
                    
                    success = successObj
                    self.pp(tag: "DebugLog", content: "DebugLog uploaded: \(success)")
                }
            } //error checking response
            else if responseCode.statusCode == 403 {
                self.pp(tag: "DebugLog", content: "sendLog failed, response code: 403")
                self.pp(tag: "DebugLog", content: "*** Needs auth, not prompting")
            }
            else if responseCode.statusCode == 500 {
                self.pp(tag: "DebugLog", content: "/api/error-logs/add returned 500. Payload: \(NSString(data: data!, encoding: String.Encoding.utf8.rawValue)!)")
            }
            else {
                self.pp(tag: "DebugLog", content: "sendLog failed: \(responseCode.statusCode)")
            }
            
            self.uploadingLog = false
            self.empty() //remove the log
        })
        
        task.resume()
    }
 
    //makes the async request using background services
    func sendLogOnExit() {
        let url = URL(string: server+"/api/error-logs/add")
        var urlRequest = URLRequest(url: url!)
        urlRequest.httpMethod = "POST"
        
        //load log into memory
        var cache = self.read()
        
        //if any data is cached, upload that as well
        if fallbackBufferCounter > 0 {
            cache.append(contentsOf: fallbackBuffer)
            fallbackBuffer.removeAll()
            fallbackBufferCounter = 0
        }
        
        self.pp(tag: "DebugLog", content: "Sending debug log")
        self.empty()
        
        let body: NSDictionary = ["log": cache]
        let jsonData: Data
        
        do {
            jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
            urlRequest.httpBody = jsonData
            
            //print json string
            //print(NSString(data: jsonData, encoding: String.Encoding.utf8.rawValue)!)
        }
        catch {
            self.pp(tag: "DebugLog", content: "Error, cannot create JSON debug log")
        }
        
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        
        //set up background configuration
        //https://realm.io/news/gwendolyn-weston-ios-background-networking/
        //https://medium.com/swift-programming/learn-nsurlsession-using-swift-part-2-background-download-863426842e21#.l6v74zgtf
        let config = URLSessionConfiguration.background(withIdentifier: "sendLogOnResign")
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: urlRequest)
        
        task.resume()
    }
}
