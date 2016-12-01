# DebugLog
A simple Swift debug logging solution, with file upload designed for iOS, and WatchOS written in Swift 3. Each `debug.log` call is appended to the end of a file (without reading the entire file each time), once the file reaches 500KB, it is uploaded to a server.

- Logs to a text file, "debug.log" in the app's Documents directory
- Log an entry with a tag prefix, e.g.

    `DebugLog.log(tag: "main", content: "bbbbbbbb")`

  Outputs (to log and console):

    `2016-10-05 16:55:07.920 | main | bbbbbbbb`
    
  If you want to suppress the message to console do:

    `debug.log(tag: "main", content: "bbbbbbbb", echo: false)`
  
- If you want to print to console only, and not the log (generally for formatting purposes), use:

    `debug.pp(tag: "main", content: "bbbbbbbb")`

- Checks if file size is greater than `500KB`, if so, it uploads it, then wipes it
- It doesn't prompt for auth, even when it needs to. The log will be removed.
  This is done to prevent any negative effects on the user experience

### Sample Implementation:

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
    debug.sendLogOnExit() to send synchoronously
 
I have it setup so whenever applicationWillResignActive is called, it uploads the log, then when applicationDidBecomeActive is called I create a new debugging session again. I do this like so:
 
    func applicationWillResignActive(_ application: UIApplication) {
        debug.log(tag: "AppDelegate", content: "applicationWillResignActive - app went from active to inactive")
        debug.sendLogOnExit()
    }
     
    func applicationDidBecomeActive(_ application: UIApplication) {
        debug.log(tag: "AppDelegate", content: "applicationDidBecomeActive - app became active")
 
        debug.enableLogging() //enable logging
        debug.empty() //remove old log (if any)
 
        debug = DebugLog(setup: true)
 
        //for the log file, dont print to console
        debug.log(tag: "AppDelegate", content: "applicationDidBecomeActive - app became active", echo: false)
    }

The server side code is your responsibility. In my case, I used CakePHP to log the request. You do not need to use CakePHP, you could use a simple PHP script. This is the format of the request, and response:

The log is sent in a POST request like so (with the parameter "DebugLog", with the value of a JSON array):

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

Created by notorious_turtle on 5/10/16.
Copyright © 2016 notorious_turtle. All rights reserved.
