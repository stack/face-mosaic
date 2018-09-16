//
//  AppDelegate.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/1/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private var windowController: WindowController? {
        for window in NSApplication.shared.windows {
            if let controller = window.windowController as? WindowController {
                return controller
            }
        }
        
        return nil
    }
    
    private var filesToOpen: [String] = []

    // MARK: - Protocols
    
    // MARK: <NSApplicationDelegate>
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        if let controller = windowController {
            controller.open(file: filename)
        } else {
            filesToOpen.append(filename)
        }
        
        return true
    }
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let controller = windowController {
            for filename in filenames {
                controller.open(file: filename)
            }
        } else {
            filesToOpen.append(contentsOf: filenames)
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if let controller = windowController {
            for file in filesToOpen {
                controller.open(file: file)
            }
            
            filesToOpen.removeAll()
        } else {
            print("Application launched without the main window controller")
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }
}

