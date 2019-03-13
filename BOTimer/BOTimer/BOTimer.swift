//
//  BOTimer.swift
//  BOTimer
//
//  Created by 凌風 on 2018/12/28.
//  Copyright © 2018年 www. All rights reserved.
//

import Foundation

class BOTimer {
    
    /// timer的状态
    ///
    /// - paused: 暂停（从未启动或已暂停）
    /// - running: 运行中
    /// - executing: 监听执行中
    /// - finished: 已完成
    public enum State: Equatable, CustomStringConvertible {
        
        case paused
        case running
        case executing
        case finished
        
        /// 实现Equatable协议
        public static func == (lhs: BOTimer.State, rhs: BOTimer.State) -> Bool {
            
            switch (lhs, rhs) {
            case (.paused, .paused),
                 (.running, .running),
                 (.executing, .executing),
                 (.finished, .finished):
                return true
            default:
                
                return false
            }
        }
        
        /// 实现CustomStringConvertible协议
        public var description: String {
            
            switch self {
            case .paused:
                return "idle/paused"
            case .running:
                return "running"
            case .finished:
                return "finished"
            case .executing:
                return "executing"
            }
        }
        
        /// 当timer正在运行或者正在执行时return True
        public var isRunning: Bool {
            
            guard self == .running || self == .executing else {
                
                return false
            }
            
            return true
        }
        
        /// 当正在执行时return True
        public var isExecuting: Bool {
            
            guard case .executing = self else {
                
                return false
            }
            
            return true
        }
        
        /// 已完成时return True
        public var isFinished: Bool {
            
            guard case .finished = self else {
                
                return false
            }
            
            return true
        }
    }
    
    
    public enum Interval {
        
        case nanoseconds(_: Int)
        case microseconds(_: Int)
        case milliseconds(_: Int)
        case minutes(_: Int)
        case seconds(_: Double)
        case hours(_: Int)
        case days(_: Int)
        
        internal var value: DispatchTimeInterval {
            
            switch self {
            case .nanoseconds(let value):
                return .nanoseconds(value)
            case .microseconds(let value):
                return .microseconds(value)
            case .milliseconds(let value):
                return .milliseconds(value)
            case .seconds(let value):
                return .milliseconds(Int(Double(value) * Double(1000)))
            case .minutes(let value):
                return .seconds(value * 60)
            case .hours(let value):
                return .seconds(value * 3600)
            case .days(let value):
                return .seconds(value * 86400)
            }
        }
    }
    
    
    /// timer 类型
    ///
    /// - infinite: 无限次数循环
    /// - finite: 有限次数循环
    /// - once: 单次
    public enum Mode {
        
        case infinite
        case finite(_: Int)
        case once
        
        /// 是否是循环timer
        internal var isRepeating: Bool {
            
            switch self {
            case .once: return false
            default: return true
            }
        }
        
        /// 循环次数
        public var iterationsCount: Int? {
            
            switch self {
            case .finite(let counts):
                return counts
            default:
                
                return nil
            }
        }
        
        /// 是否是无限循环
        public var isInfinite: Bool {
            
            guard case .infinite = self else {
                
                return false
            }
            
            return true
        }
    }
    
    /// 回调的别名
    public typealias Observer = ((BOTimer) -> Void)
    
    /// Token
    public typealias ObserverToken = UInt64
    
    /// 当前状态
    public private(set) var state: State = .paused {
        
        didSet {
            
            // 状态改变的回调
            self.onStateChanged?(self, state)
        }
    }
    
    /// 状态改变时的回调
    public var onStateChanged: ((_ timer: BOTimer, _ state: State) -> Void)?
    
    /// timer的所有监听者
    private var observers = [ObserverToken: Observer]()
    
    /// timer的下一个监听者ID
    private var nextObserverID: UInt64 = 0
    
    /// Internal GCD Timer
    private var timer: DispatchSourceTimer?
    
    /// timer 类型
    public private(set) var mode: Mode
    
    /// timer循环次数
    public private(set) var remainingIterations: Int?
    
    /// timer循环时间
    private var interval: Interval
    
    /// timer的误差
    private var tolerance: DispatchTimeInterval
    
    /// timer所在的线程
    private var queue: DispatchQueue?
    
    /// 初始化BOTimer
    ///
    /// - Parameters:
    ///   - interval: 循环时间
    ///   - mode: 类型
    ///   - tolerance: 误差
    ///   - queue: 线程
    ///   - observer: 监听者
    public init(interval: Interval, mode: Mode = .infinite, tolerance: DispatchTimeInterval = .nanoseconds(0), queue: DispatchQueue? = nil, observer: @escaping Observer) {
        
        self.mode = mode
        self.interval = interval
        self.tolerance = tolerance
        self.remainingIterations = mode.iterationsCount
        self.queue = (queue ?? DispatchQueue(label: "com.BOTimer.queue"))
        self.timer = configureTimer()
        self.observe(observer)
    }
    
    /// 添加监听者
    ///
    /// - Parameter observer: 监听者
    /// - Returns: 监听者ID
    @discardableResult
    public func observe(_ observer: @escaping Observer) -> ObserverToken {
        
        // 生成token是判断是否溢出，溢出时置0
        var (new, overflow) = self.nextObserverID.addingReportingOverflow(1)
        
        if overflow {
            
            self.nextObserverID = 0
            
            new = 0
        }
        
        self.nextObserverID = new
        
        self.observers[new] = observer
        
        return new
    }
    
    /// 移除监听者
    ///
    /// - Parameter identifier: 监听者ID
    public func remove(observer identifier: ObserverToken) {
        
        self.observers.removeValue(forKey: identifier)
    }
    
    /// 移除所有监听者
    ///
    /// - Parameter stopTimer: 是否需要停止计时器
    public func removeAllObservers(thenStop stopTimer: Bool = false) {
        
        self.observers.removeAll()
        
        if stopTimer { self.pause() }
    }
    
    /// 配置timer
    ///
    /// - Returns: 使用GCD Timer
    private func configureTimer() -> DispatchSourceTimer {
        
        let associatedQueue = (queue ?? DispatchQueue(label: "com.BOTimer.\(NSUUID().uuidString)"))
        
        let timer = DispatchSource.makeTimerSource(queue: associatedQueue)
        
        let repeatInterval = interval.value
        
        let deadline: DispatchTime = (DispatchTime.now() + repeatInterval)
        
        if self.mode.isRepeating {
            
            timer.schedule(deadline: deadline, repeating: repeatInterval, leeway: tolerance)
        } else {
            
            timer.schedule(deadline: deadline, leeway: tolerance)
        }
        
        timer.setEventHandler {
            [weak self] in
            
            if let unwrapped = self {
                
                unwrapped.timerFired()
            }
        }
        
        return timer
    }
    
    /// 销毁当前timer
    private func destroyTimer() {
        
        self.timer?.setEventHandler(handler: nil)
        
        self.timer?.cancel()
        
        if state == .paused || state == .finished {
            
            self.timer?.resume()
        }
    }
    
    /// 创建单次timer，某个时间之后执行
    ///
    /// - Parameters:
    ///   - interval: 延迟时间
    ///   - tolerance: 误差
    ///   - queue: 线程
    ///   - observer: 监听者
    /// - Returns: BOTimer
    @discardableResult
    public class func once(after interval: Interval, tolerance: DispatchTimeInterval = .nanoseconds(0), queue: DispatchQueue? = nil, _ observer: @escaping Observer) -> BOTimer {
        
        let timer = BOTimer(interval: interval, mode: .once, tolerance: tolerance, queue: queue, observer: observer)
        
        timer.start()
        
        return timer
    }
    
    /// 创建循环timer，每隔一段时间执行一次，可配置执行次数
    ///
    /// - Parameters:
    ///   - interval: 间隔时间
    ///   - repeatCount: 执行次数
    ///   - tolerance: 误差
    ///   - queue: 线程
    ///   - observer: 监听者
    /// - Returns: BOTimer
    @discardableResult
    public class func every(_ interval: Interval, repeatCount: Int? = nil, tolerance: DispatchTimeInterval = .nanoseconds(0), queue: DispatchQueue? = nil, _ observer: @escaping Observer) -> BOTimer {
        
        let mode: Mode = (repeatCount != nil ? .finite(repeatCount!) : .infinite)
        
        let timer = BOTimer(interval: interval, mode: mode, tolerance: tolerance, queue: queue, observer: observer)
        
        timer.start()
        
        return timer
    }
    
    /// 启动
    ///
    /// - Parameter pause: 启动后是否暂停
    public func fire(andPause pause: Bool = false) {
        
        self.timerFired()
        
        if pause {
            
            self.pause()
        }
    }
    
    /// 重置timer
    ///
    /// - Parameters:
    ///   - interval: 间隔时间
    ///   - restart: 是否重新启动
    public func reset(_ interval: Interval?, restart: Bool = true) {
        
        if self.state.isRunning {
            
            self.setPause(from: self.state)
        }
        
        if case .finite(let count) = self.mode {
            
            self.remainingIterations = count
        }
        
        if let newInterval = interval {
            
            self.interval = newInterval
        }
        
        self.destroyTimer()
        
        self.timer = configureTimer()
        
        self.state = .paused
        
        if restart {
            
            self.timer?.resume()
            
            self.state = .running
        }
    }
    
    /// 启动timer
    ///
    /// - Returns: 是否重新启动
    @discardableResult
    public func start() -> Bool {
        
        guard self.state.isRunning == false else {
            
            return false
        }
        
        guard self.state.isFinished == true else {
            
            self.state = .running
            
            self.timer?.resume()
            
            return true
        }
        
        self.reset(nil, restart: true)
        
        return true
    }
    
    /// 暂停正在运行中的Timer
    ///
    /// - Returns: 是否暂停
    @discardableResult
    public func pause() -> Bool {
        
        guard self.state != .paused && self.state != .finished else {
            
            return false
        }
        
        return self.setPause(from: self.state)
    }
    
    /// 暂停timer，同时改变timer状态
    ///
    /// - Parameters:
    ///   - currentState: 当前状态
    ///   - newState: 新的状态
    /// - Returns: 是否暂停
    @discardableResult
    private func setPause(from currentState: State, to newState: State = .paused) -> Bool {
        
        guard self.state == currentState else {
            
            return false
        }
        
        self.timer?.suspend()
        
        self.state = newState
        
        return true
    }
    
    /// timer启动时执行
    private func timerFired() {
        
        self.state = .executing
        
        if case .finite = self.mode {
            
            self.remainingIterations! -= 1
        }
        
        self.observers.values.forEach { $0(self) }
        
        switch self.mode {
        case .once:
            
            self.setPause(from: .executing, to: .finished)
        case .finite:
            
            if self.remainingIterations! == 0 {
                
                self.setPause(from: .executing, to: .finished)
            }
        case .infinite:
            
            break
        }
    }
    
    deinit {
        
        self.observers.removeAll()
        
        self.destroyTimer()
    }
}

extension BOTimer: Equatable {
    
    static func == (lhs: BOTimer, rhs: BOTimer) -> Bool {
        
        return lhs === rhs
    }
}
