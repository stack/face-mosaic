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
    
    private var windowController: WindowController? = nil
    
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
        guard let controller = NSApplication.shared.mainWindow?.windowController as? WindowController else {
            print("Application launched without the main window controller")
            return
        }
        
        for file in filesToOpen {
            controller.open(file: file)
        }
        
        windowController = controller
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }
}

