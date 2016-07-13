//
//  ViewController.swift
//  HelloOpenGL_Swift
//
//  Created by DR on 8/25/15.
//  Copyright © 2015 DR. All rights reserved.
//

import UIKit
import AVFoundation

/**
 This controller does 2 things:
 - setup and launch the video (from local file)
 - when asked for, pass a pixel buffer from the video (that will be used for GL rendering)
 **/
class ViewController: UIViewController {
    var glView: OpenGLView!

    // video things
    var videoOutput: AVPlayerItemVideoOutput!
    var player: AVPlayer!
    var playerItem: AVPlayerItem!
    var isVideoReady = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        let frame = UIScreen.main().bounds
        glView = OpenGLView(frame: frame, viewWillRender: onGlRefresh)
        self.view.addSubview(glView)

        self.setupVideo()
    }

    func setupVideo() -> Void {
        let url = Bundle.main.urlForResource("big_buck_bunny", withExtension: "mp4")!

        // since all openGl - video example use YUV color, we do the same
        let outputSettings: [String: AnyObject] = ["kCVPixelBufferPixelFormatTypeKey": Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)]

        self.videoOutput = AVPlayerItemVideoOutput.init(pixelBufferAttributes: outputSettings)
        self.player = AVPlayer()
        let asset = AVURLAsset(url: url)

        asset.loadValuesAsynchronously(forKeys: ["playable"]) {
            var error: NSError? = nil
            let status = asset.statusOfValue(forKey: "playable", error: &error)
            switch status {
            case .loaded:
                self.playerItem = AVPlayerItem(asset: asset)
                self.playerItem.add(self.videoOutput)
                self.player.replaceCurrentItem(with: self.playerItem)
                self.isVideoReady = true
                self.player.play()
            // Sucessfully loaded, continue processing
            default:
                print("error")
                // Handle all other cases
            }
        }
    }

    /**
     This function is called by the openGL view when the view is preparing for rendering
    **/
    func onGlRefresh(glView: OpenGLView) -> Void {
        if self.isVideoReady {
            let pixelBuffer = self.videoOutput.copyPixelBuffer(forItemTime: self.playerItem.currentTime(), itemTimeForDisplay: nil)
            glView.pixelBuffer = pixelBuffer
        }
    }

    override func prefersStatusBarHidden() -> Bool {
        return true
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}
