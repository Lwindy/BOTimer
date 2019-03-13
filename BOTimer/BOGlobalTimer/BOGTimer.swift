//
//  BOGTimer.swift
//  BOTimer
//
//  Created by 凌風 on 2019/1/2.
//  Copyright © 2019年 www. All rights reserved.
//

import Foundation

class BOGEvent {
    
    typealias Observer = (([AnyHashable: Any]?)->Void)
    
    private(set) var identifier: String!
    
    var interval: Int
    
    var creatAt: Int
    
    var observer: Observer?
    
    var isRepeat: Bool
    
    var isActive: Bool
    
    var userInfo: [AnyHashable: Any]?
    
    init() {
        
        self.isRepeat = true
        self.isActive = true
        self.interval = 0
        self.creatAt = 0
        
        self.userInfo = [AnyHashable: Any]()
    }
    
    class func event(with identifier: String) -> BOGEvent {
        
        let e = BOGEvent()
        e.identifier = identifier
        
        return e
    }
}

class BOGTimer {
    
    static let `default` = BOGTimer()
    
    private var defaultTimerInterval: Int = 1
    
    private var indexInterval: Int = 0
    
    private var events: [BOGEvent] = [BOGEvent]()
    
    private var queue: DispatchQueue? = nil
    
    private var timer: DispatchSourceTimer?
    
    private var tolerance: DispatchTimeInterval = .nanoseconds(0)
    
    private let lock = NSLock()
    
    init() {
        
        self.queue = DispatchQueue(label: "com.BOGTimer.queue")
        
        self.timer = configureTimer()
        
    }
    
    
    public func scheduled(with identifier: String, timeInterval interval: Int, isRepeat: Bool, observer: @escaping BOGEvent.Observer, userInfo: [AnyHashable: Any]?) {
        
        var shouldSkip = false
        
        for event in self.events {
            
            shouldSkip = (event.identifier == identifier)
            
            if shouldSkip { break }
        }
        
        if shouldSkip { return }
        
        // 执行observer
        self.queue?.async {
            
             observer(userInfo)
        }
        
        if !isRepeat { return }
        
        lock.lock()
        
        let event = BOGEvent.event(with: identifier)
        
        event.interval = interval
        
        event.creatAt = self.indexInterval % interval
        
        event.observer = observer
        
        event.isRepeat = isRepeat
        
        event.userInfo = userInfo
        
        self.events.append(event)
        
        lock.unlock()
    }
    
    public func updateEvent(with identifier: String, timeInterval interval: Int, isRepeat: Bool = true, obsesrver: BOGEvent.Observer? = nil, userInfo: [AnyHashable: Any]? = nil) {
        
        for event in self.events {
            
            if event.identifier == identifier {
                
                event.interval = interval != 0 ? interval : event.interval
                
                event.isRepeat = isRepeat
                
                event.observer = obsesrver ?? event.observer
                
                event.userInfo = userInfo ?? event.userInfo
            }
        }
    }
    
    public func activeEvent(with identifier: String) {
        
        for event in self.events {
            
            if event.identifier == identifier {
                
                event.isActive = true
            }
        }
    }
    
    public func pauseEvent(with identifier: String) {
        
        for event in self.events {
            
            if event.identifier == identifier {
                
                event.isActive = false
            }
        }
    }
    
    public func removeEvent(with identifier: String) {
        
        let index = self.events.index { (event) -> Bool in
            
            return event.identifier == identifier
        }
        
        guard index != nil else {
            
            return
        }
        
        self.events.remove(at: index!)
    }
    
    private func destroyTimer() {
        
        self.timer?.setEventHandler(handler: nil)
        
        self.timer?.cancel()
    }
    
    private func configureTimer() -> DispatchSourceTimer {
        
        let associatedQueue = (queue ?? DispatchQueue(label: "com.BOTimer.\(NSUUID().uuidString)"))
        
        let timer = DispatchSource.makeTimerSource(queue: associatedQueue)
        
        let repeatInterval = DispatchTimeInterval.seconds(self.defaultTimerInterval)
        
        let deadline: DispatchTime =  (DispatchTime.now() + repeatInterval)
        
        timer.schedule(deadline: deadline, repeating: repeatInterval, leeway: self.tolerance)
        
        timer.setEventHandler {
            [weak self] in
            
            if let unwrapped = self {
                
                unwrapped.timerFired()
            }
        }
        
        timer.resume()
        
        return timer
    }
    
 
    private func timerFired() {
        
        self.indexInterval += self.defaultTimerInterval
        
        for event in self.events {
            
            let blockQueueName = "com.BOGTimer." + event.identifier
            
            let blockQueue = DispatchQueue(label: blockQueueName)
            
            blockQueue.async {
                
                let executeable = (event.interval != 0 &&  (self.indexInterval - event.creatAt) % event.interval == 0 && event.isActive && event.observer != nil)
                
                if executeable {
                    
                    event.observer!(event.userInfo)
                }
            }
        }
        
        let lcmValue = self.lcmInterval()
        
        if self.indexInterval > lcmValue && lcmValue != 0 {
            
            self.indexInterval = self.indexInterval % lcmValue
        }
    }
    
    
    private func lcmInterval() -> Int {
        
        var arr = [Int]()
        
        for event in self.events {
            
            arr.append(event.interval)
        }
        
        return findLCM(arr: arr, count: self.events.count)
    }
    
    deinit {
        
        self.destroyTimer()
    }
}

func findLCM(arr: [Int], count: Int) -> Int {
    
    var result = arr[0]
    
    for i in 1..<count {
        
        result = lcm(a: arr[i], b: result)
    }
    
    return result
}

func lcm(a: Int, b: Int) -> Int {
    
    return a * b / gcd(a: min(a, b), b: max(a, b))
}

func gcd(a: Int, b: Int) -> Int {
    
    if a == 0 {
        
        return b
    }
    
    return gcd(a: b % a, b: a)
}
