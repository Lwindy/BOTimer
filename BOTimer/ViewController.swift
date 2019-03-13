//
//  ViewController.swift
//  BOTimer
//
//  Created by 凌風 on 2018/12/28.
//  Copyright © 2018年 www. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    var timer2: BOTimer?
    
    @IBOutlet weak var pauseBtn: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        
        print("开始时间\(Date())")
        
        let timer = BOTimer.once(after: .seconds(5)) { (timer) in
            
            print("时间到\(Date())")
        }
        
        print("Allocated timer \(timer)")
        
        /*
        self.timer2 = BOTimer.every(.seconds(3)) { (timer) in
            
            print("执行时间\(Date())")
        }*/
        
        var count = 0
        
        self.timer2 = BOTimer.every(.seconds(2), repeatCount: 10, queue: nil, { (timer) in
            count += 1
            
            print(count)
        })
        
        BOGTimer.default.scheduled(with: "1", timeInterval: 2, isRepeat: true, observer: { (dict) in
            
            print("\(dict)" + "时间: \(Date())")
            
        }, userInfo: ["user": "windy"])
        
        BOGTimer.default.scheduled(with: "2", timeInterval: 3, isRepeat: true, observer: { (dict) in
            
            print("\(dict)" + "时间: \(Date())")
            
        }, userInfo: ["user": "ff"])
    }

    // MARK:- Action
    @IBAction func onPauseBtnClicked(_ sender: UIButton) {
        
        sender.isSelected = !sender.isSelected
        
        if sender.isSelected {
            
            self.timer2?.pause()
        } else {
            
            self.timer2?.start()
        }
    }
    
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

