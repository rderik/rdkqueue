import Foundation

class Server {
    
    let servicePort = "1234"
    let prompts = ["%", "$", ">"]
    var currentPrompt = 0
    var clients = [Int32]() //File descriptors are represented by Int32
    
    func setReloadPromptObserver() {
        let reloadKqueue = kqueue()
        if reloadKqueue == -1 {
            print("Error creating prompt kqueue")
            exit(EXIT_FAILURE)
        }
       
        let fileTrigger = open(FileManager.default.fileSystemRepresentation(withPath: "./change_prompt.txt"), O_EVTONLY)
        guard fileTrigger >= 0 else {
            print("Error: there was an error reading ./change_prompt.txt")
            return
        }
        
        var fileKevent = kevent(
            ident: UInt(fileTrigger),
            filter: Int16(EVFILT_VNODE),
            flags: UInt16(EV_ADD | EV_ENABLE),
            fflags: UInt32(NOTE_ATTRIB),
            data: 0,
            udata: nil
        )
        
        kevent(reloadKqueue, &fileKevent, 1, nil, 0, nil)
        
        DispatchQueue.global(qos: .default).async {
            var event = kevent()
                let status = kevent(reloadKqueue, nil, 0, &event, 1, nil)
                self.currentPrompt = (self.currentPrompt + 1) % self.prompts.count
                if  status == 0 {
                    print("Timeout")
                } else if status > 0 {
                    
                } else {
                    print("Error reading kevent")
                    close(reloadKqueue)
                }
            self.setReloadPromptObserver()
        }
        print("Completed Set Reload Prompt")
    }
    
    func stop() {
        for client in clients {
            writeTo(socket: client, message: "Server shutting down")
            close(client)
        }
    }
    
    func writeTo(socket fd: Int32, message: String) {
        write(fd, message.cString(using: .utf8), message.count)
    }
    
    func readFrom(socket fd: Int32) {
      let MTU = 65536
      var buffer = UnsafeMutableRawPointer.allocate(byteCount: MTU,alignment: MemoryLayout<CChar>.size)

      let readResult = read(fd, &buffer, MTU)

      if (readResult == 0) {
        return  // end of file
      } else if (readResult == -1) {
        print("Error reading form client\(fd) - \(errno)")
        return  // error
      } else {
        //This is an ugly way to add the null-terminator at the end of the buffer we just read
        withUnsafeMutablePointer(to: &buffer) {
          $0.withMemoryRebound(to: UInt8.self, capacity: readResult + 1) {
            $0.advanced(by: readResult).assign(repeating: 0, count: 1)
          }
        }
        let strResult = withUnsafePointer(to: &buffer) {
          $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: readResult)) {
            String(cString: $0)
          }
        }
        print("Received form client(\(fd)) \(self.prompts[self.currentPrompt]) \(strResult)")
        write(fd, &buffer, readResult)
      }
    }
    
    func setSockKqueue(fd: Int32) {
        let sockKqueue = kqueue()
        if sockKqueue == -1 {
            print("Error creating kqueue")
            exit(EXIT_FAILURE)
        }
        
        
        // Create the kevent structure that sets up our kqueue to listen
        // for notifications
        var sockKevent = kevent(
            ident: UInt(fd),
            filter: Int16(EVFILT_READ),
            flags: UInt16(EV_ADD | EV_ENABLE),
            fflags: 0,
            data: 0,
            udata: nil
        )
        // This is where the kqueue is register with our 
        // interest for the notifications described by
        // our kevent structure sockKevent
        kevent(sockKqueue, &sockKevent, 1, nil, 0, nil)
        
        
        DispatchQueue.global(qos: .default).async {
            var event = kevent()
            while true {
                let status = kevent(sockKqueue, nil, 0, &event, 1, nil)
                if  status == 0 {
                    print("Timeout")
                } else if status > 0 {
                    if (event.flags & UInt16(EV_EOF)) == EV_EOF {
                        print("The socket (\(fd)) has been closed.")
                        if let index = self.clients.firstIndex(of: fd) {
                            self.clients.remove(at: index)
                        }
                        break
                    }
                    print("File descriptor: \(fd) - has \(event.data) characters for reading")
                    self.readFrom(socket: fd)
                } else {
                    print("Error reading kevent")
                    close(sockKqueue)
                    exit(EXIT_FAILURE)
                }
            }
            print("Bye from kevent")
        }
    }
    
    func start() {
        print("Server starting...")
        
        let socketFD = socket(AF_INET6, //Domain [AF_INET,AF_INET6, AF_UNIX]
            SOCK_STREAM, //Type [SOCK_STREAM, SOCK_DGRAM, SOCK_SEQPACKET, SOCK_RAW]
            IPPROTO_TCP  //Protocol [IPPROTO_TCP, IPPROTO_SCTP, IPPROTO_UDP, IPPROTO_DCCP]
        )//Return a FileDescriptor -1 = error
        if socketFD == -1 {
            print("Error creating BSD Socket")
            return
        }
        
        var hints = addrinfo(
            ai_flags: AI_PASSIVE,       // Assign the address of the local host to the socket structures
            ai_family: AF_UNSPEC,       // Either IPv4 or IPv6
            ai_socktype: SOCK_STREAM,   // TCP
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil)
        
        var servinfo: UnsafeMutablePointer<addrinfo>? = nil
        let addrInfoResult = getaddrinfo(
            nil,                        // Any interface
            servicePort,                   // The port on which will be listenend
            &hints,                     // Protocol configuration as per above
            &servinfo)
        
        if addrInfoResult != 0 {
            print("Error getting address info: \(errno)")
            return
        }
        
        let bindResult = bind(socketFD, servinfo!.pointee.ai_addr, socklen_t(servinfo!.pointee.ai_addrlen))
        
        if bindResult == -1 {
            print("Error binding socket to Address: \(errno)")
            return
        }
        
        let listenResult = listen(socketFD, //Socket File descriptor
            8         // The backlog argument defines the maximum length the queue of pending connections may grow to
        )
        
        if listenResult == -1 {
            print("Error setting our socket to listen")
            return
        }
        
        while true {
            var addr = sockaddr()
            var addr_len :socklen_t = 0
            
            print("About to accept")
            let clientFD = accept(socketFD, &addr, &addr_len)
            print("Accepted new client with file descriptor: \(clientFD)")
            
            if clientFD == -1 {
                print("Error accepting connection")
                continue
            }
            clients.append(clientFD)
            
            setSockKqueue(fd: clientFD)
            setReloadPromptObserver()
        }
    }
}
