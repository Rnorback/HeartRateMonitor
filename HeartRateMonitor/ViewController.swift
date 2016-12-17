//
//  ViewController.swift
//  HeartRateMonitor
//
//  Created by Rob Norback on 12/15/16.
//  Copyright © 2016 Norback Solutions, LLC. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {
        
    @IBOutlet var heartRate: UILabel!
    @IBOutlet var secondsPassed: UILabel!
    @IBOutlet var spinner: UIActivityIndicatorView!
    
    var heartRateDetectionModel = HeartRateDetectionModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        heartRateDetectionModel.delegate = self
    }

    @IBAction func startDetectionButtonPressed(_ sender: UIButton) {
        heartRateDetectionModel.startDetection()
    }

}

extension ViewController: HeartRateDetectionModelDelegate {
    
    func heartRateStart() {
        spinner.startAnimating()
    }
    
    func heartRateUpdate(bpm:Int, atTime seconds:Int) {
        heartRate.text = String(bpm)
        secondsPassed.text = String(seconds)
    }
    
    func heartRateEnd() {
        spinner.stopAnimating()
    }
}
