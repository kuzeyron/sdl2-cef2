// Copyright (c) 2017 The Chromium Embedded Framework Authors.
// Portions copyright (c) 2010 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "examples/shared/main.h"

#import <Cocoa/Cocoa.h>

#include "include/cef_application_mac.h"
#include "include/wrapper/cef_helpers.h"

#include "examples/shared/app_factory.h"
#include "examples/shared/client_manager.h"

// Receives notifications from the application.
@interface SharedAppDelegate : NSObject<NSApplicationDelegate>
- (void)createApplication:(id)object;
- (void)tryToTerminateApplication:(NSApplication*)app;
@end

// Provide the CefAppProtocol implementation required by CEF.
@interface SharedApplication : NSApplication<CefAppProtocol> {
 @private
  BOOL handlingSendEvent_;
}
@end

@implementation SharedApplication
- (BOOL)isHandlingSendEvent {
  return handlingSendEvent_;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  handlingSendEvent_ = handlingSendEvent;
}

- (void)sendEvent:(NSEvent*)event {
  CefScopedSendingEvent sendingEventScoper;
  [super sendEvent:event];
}

// |-terminate:| is the entry point for orderly "quit" operations in Cocoa. This
// includes the application menu's quit menu item and keyboard equivalent, the
// application's dock icon menu's quit menu item, "quit" (not "force quit") in
// the Activity Monitor, and quits triggered by user logout and system restart
// and shutdown.
//
// The default |-terminate:| implementation ends the process by calling exit(),
// and thus never leaves the main run loop. This is unsuitable for Chromium
// since Chromium depends on leaving the main run loop to perform an orderly
// shutdown. We support the normal |-terminate:| interface by overriding the
// default implementation. Our implementation, which is very specific to the
// needs of Chromium, works by asking the application delegate to terminate
// using its |-tryToTerminateApplication:| method.
//
// |-tryToTerminateApplication:| differs from the standard
// |-applicationShouldTerminate:| in that no special event loop is run in the
// case that immediate termination is not possible (e.g., if dialog boxes
// allowing the user to cancel have to be shown). Instead, this method tries to
// close all browsers by calling CloseBrowser(false) via
// ClientHandler::CloseAllBrowsers. Calling CloseBrowser will result in a call
// to ClientHandler::DoClose and execution of |-performClose:| on the NSWindow.
// DoClose sets a flag that is used to differentiate between new close events
// (e.g., user clicked the window close button) and in-progress close events
// (e.g., user approved the close window dialog). The NSWindowDelegate
// |-windowShouldClose:| method checks this flag and either calls
// CloseBrowser(false) in the case of a new close event or destructs the
// NSWindow in the case of an in-progress close event.
// ClientHandler::OnBeforeClose will be called after the CEF NSView hosted in
// the NSWindow is dealloc'ed.
//
// After the final browser window has closed ClientHandler::OnBeforeClose will
// begin actual tear-down of the application by calling CefQuitMessageLoop.
// This ends the NSApplication event loop and execution then returns to the
// main() function for cleanup before application termination.
//
// The standard |-applicationShouldTerminate:| is not supported, and code paths
// leading to it must be redirected.
- (void)terminate:(id)sender {
  SharedAppDelegate* delegate =
      static_cast<SharedAppDelegate*>([NSApp delegate]);
  [delegate tryToTerminateApplication:self];
  // Return, don't exit. The application is responsible for exiting on its own.
}
@end

@implementation SharedAppDelegate

// Create the application on the UI thread.
- (void)createApplication:(id)object {
  [NSApplication sharedApplication];
  [[NSBundle mainBundle] loadNibNamed:@"MainMenu"
                                owner:NSApp
                      topLevelObjects:nil];

  // Set the delegate for application events.
  [[NSApplication sharedApplication] setDelegate:self];
}

- (void)tryToTerminateApplication:(NSApplication*)app {
  shared::ClientManager* manager = shared::ClientManager::GetInstance();
  if (manager && !manager->IsClosing())
    manager->CloseAllBrowsers(false);
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication*)sender {
  return NSTerminateNow;
}
@end

namespace shared {

// Entry point function for the browser process.
int main(int argc, char* argv[]) {
  // Initialize the AutoRelease pool.
  NSAutoreleasePool* autopool = [[NSAutoreleasePool alloc] init];

  // Provide CEF with command-line arguments.
  CefMainArgs main_args(argc, argv);

  // Create a CefApp for the browser process. Other processes are handled by
  // process_helper_mac.cc.
  CefRefPtr<CefApp> app = CreateBrowserProcessApp();

  // Initialize the SharedApplication instance.
  [SharedApplication sharedApplication];

  // Create the singleton manager instance.
  ClientManager manager;

  // Specify CEF global settings here.
  CefSettings settings;

  // Initialize CEF for the browser process. The first browser instance will be
  // created in CefBrowserProcessHandler::OnContextInitialized() after CEF has
  // been initialized.
  CefInitialize(main_args, settings, app, NULL);

  // Create the application delegate.
  NSObject* delegate = [[SharedAppDelegate alloc] init];
  [delegate performSelectorOnMainThread:@selector(createApplication:)
                             withObject:nil
                          waitUntilDone:NO];

  // Run the CEF message loop. This will block until CefQuitMessageLoop() is
  // called.
  CefRunMessageLoop();

  // Shut down CEF.
  CefShutdown();

  // Release the delegate.
  [delegate release];

  // Release the AutoRelease pool.
  [autopool release];

  return 0;
}

}  // namespace shared
