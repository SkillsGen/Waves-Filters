//
//  UIDialImageView.swift
//  SoundTest5
//
//  Created by Sebastian Reinolds on 17/07/2018.
//  Copyright © 2018 Sebastian Reinolds. All rights reserved.
//

import UIKit

class UIDialImageView: UIImageView {
    let viewForGesture: UIView
    
    var value: Float!
    var valMin: Float!
    var valMax: Float!
    
    var angleMinOffset: CGFloat!
    var initialAngle: CGFloat = -0.22
    var angle: CGFloat = -0.22
    
    init(frame: CGRect, viewForGesture: UIView, angleMinOffset: CGFloat, valMin: Float, valMax: Float, initialValue: Float) {
        self.viewForGesture = viewForGesture
        self.angleMinOffset = angleMinOffset
        
        self.value = valMin
        self.valMin = valMin
        self.valMax = valMax
        
        super.init(frame: frame)
        
        let freqDialGesture = UIPanGestureRecognizer(target: self, action: #selector(dialGesture(_:)))
        self.addGestureRecognizer(freqDialGesture)
        self.isUserInteractionEnabled = true
        
        updateByValue(initialValue)
    }
    
    func updateByValue(_ value: Float) {
        if value < self.valMin {
            self.value = self.valMin
        } else if value > self.valMax {
            self.value = self.valMax
        } else {
            self.value = value
        }
        self.angle = CGFloat((self.value - self.valMin) * (3.14 / valMax) + Float(self.angleMinOffset))
        self.initialAngle = self.angle
        self.transform = CGAffineTransform(rotationAngle: self.angle)
    }
    
    func updateByAngle(_ angle: CGFloat) {
        if angle < self.angleMinOffset {
            self.angle = self.angleMinOffset
        } else if angle > self.angleMinOffset + 3.14 {
            self.angle = self.angleMinOffset + 3.14
        } else {
            self.angle = angle
        }
        self.value = Float(self.angle - self.angleMinOffset) * (self.valMax / 3.14) + self.valMin
        
        self.transform = CGAffineTransform(rotationAngle: self.angle)
    }
    
    @objc func dialGesture(_ gesture: UIPanGestureRecognizer) {
        let newAngle = gesture.translation(in: self.viewForGesture).y / -50
        
        updateByAngle(self.initialAngle + newAngle)
        
        if gesture.state == .ended {
            self.initialAngle = self.angle
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
