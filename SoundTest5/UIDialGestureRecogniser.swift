//
//  UIDialGestureRecogniser.swift
//  SoundTest5
//
//  Created by Sebastian Reinolds on 17/07/2018.
//  Copyright © 2018 Sebastian Reinolds. All rights reserved.
//

import UIKit
import UIKit.UIGestureRecognizerSubclass

class UIDialGestureRecogniser: UIPanGestureRecognizer {
    var touchAngle: CGFloat = 0
    var lastTouchPoint: CGPoint = CGPoint(x: 0, y: 0)
    
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        
        maximumNumberOfTouches = 1
        minimumNumberOfTouches = 1
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        lastTouchPoint = touches.first!.location(in: self.view)
        
        updateAngle(with: touches)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        
        updateAngle(with: touches)
    }
    
    func updateAngle(with touches: Set<UITouch>) {
        if let touch = touches.first,
           let view = self.view {
            let touchPoint = touch.location(in: view)
            let offset = CGPoint(x: touchPoint.x - view.bounds.midX, y: touchPoint.y - view.bounds.midY)
            print(touchPoint)
            touchAngle = atan2(offset.y, offset.x)
        }
    }
}
