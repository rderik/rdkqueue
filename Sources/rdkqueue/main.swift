import Foundation

print("Welcome to our simple echo server!")


var server = Server()


func setSignalKqueue() {
    print("Setting up Signal Handler")
    let sockKqueue = kqueue()
    if sockKqueue == -1 {
        print("Error creating kqueue")
        exit(EXIT_FAILURE)
    }
    
    // the signal API takes precedence over kqueue event handling
    // to avoid this behaviour we are going to ignore the SIGTERM
    // and handle it using our kqueue implementation
    signal (SIGTERM, SIG_IGN);
    
    
    var edit = kevent(
        ident: UInt(SIGTERM),
        filter: Int16(EVFILT_SIGNAL),
        flags: UInt16(EV_ADD | EV_ENABLE),
        fflags: 0,
        data: 0,
        udata: nil
    )
    kevent(sockKqueue, &edit, 1, nil, 0, nil)
    
    
    DispatchQueue.global(qos: .default).async {
        while true {
            var event = kevent()
            let status = kevent(sockKqueue, nil, 0, &event, 1, nil)
            if  status == 0 {
                print("Timeout")
            } else if status > 0 {
                print("We got a terminate signal! \(event)")
                server.stop()
                exit(130) //Exit code for "Script terminated by Control-C"
            } else {
                print("Error reading kevent")
                close(sockKqueue)
                exit(EXIT_FAILURE)
            }
        }
    }
}
setSignalKqueue()
server.start()



RunLoop.main.run()
exit(EXIT_SUCCESS)
