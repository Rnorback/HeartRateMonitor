//
//  ViewController.swift
//  HeartRateMonitor
//
//  Created by Rob Norback on 12/15/16.
//  Copyright © 2016 Norback Solutions, LLC. All rights reserved.
//

import UIKit
import AVFoundation
import Charts

class ViewController: UIViewController {
        
    @IBOutlet var heartRate: UILabel!
    @IBOutlet var secondsPassed: UILabel!
    @IBOutlet var spinner: UIActivityIndicatorView!
    @IBOutlet var lineChartView: LineChartView!
    @IBOutlet var stopStartButton: UIButton!
    
    var heartRateDetectionModel = HeartRateDetectionModel()
    var chartDataEntries:[ChartDataEntry] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        heartRateDetectionModel.delegate = self
        
        lineChartView.legend.enabled = false
        lineChartView.chartDescription?.text = ""
        lineChartView.borderColor = UIColor.black
        lineChartView.xAxis.labelPosition = .bottom
    }

    @IBAction func startDetectionButtonPressed(_ sender: UIButton) {
        
        if sender.titleLabel?.text == "Start" {
            heartRateDetectionModel.startDetection()
            sender.setTitle("Stop", for: .normal)
        }
        else if sender.titleLabel?.text == "Stop" {
            heartRateDetectionModel.stopDetection()
            sender.setTitle("Start", for: .normal)
        }
    }

}

extension ViewController: HeartRateDetectionModelDelegate {
    
    func heartRateStart() {
        spinner.startAnimating()
        chartDataEntries = []
    }
    
    func heartRateRawData(data:CGFloat) {
        //update graph data
        let entry = ChartDataEntry(x: Double(chartDataEntries.count), y: Double(data))
        chartDataEntries.append(entry)
    }
    
    func heartRateUpdate(bpm:Int, atTime seconds:Int) {
        heartRate.text = String(bpm)
        secondsPassed.text = String(seconds)
        
        //update graph
        let dataSet = LineChartDataSet(values: chartDataEntries, label: "Raw Heart Data")
        dataSet.lineWidth = 3.0
        dataSet.setColor(UIColor(red: 0.169, green: 0.424, blue: 0.624, alpha: 1.00))
        dataSet.highlightColor = UIColor.gray
        dataSet.drawValuesEnabled = false
        dataSet.drawCirclesEnabled = false
        
        lineChartView.data = LineChartData(dataSet: dataSet)
    }
    
    func heartRateEnd() {
        spinner.stopAnimating()
        stopStartButton.setTitle("Start", for: .normal)
    }
}
