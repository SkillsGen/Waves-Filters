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
    
    var initialAngle: CGFloat = -0.22
    var angle: CGFloat = -0.22
    
    init(frame: CGRect, viewForGesture: UIView) {
        self.viewForGesture = viewForGesture
        super.init(frame: frame)
        
        let freqDialGesture = UIPanGestureRecognizer(target: self, action: #selector(dialGesture(_:)))
        self.addGestureRecognizer(freqDialGesture)
        self.isUserInteractionEnabled = true
    }
    
    @objc func dialGesture(_ gesture: UIPanGestureRecognizer) {
        let newAngle = gesture.translation(in: self.viewForGesture).y / -50
        
        var rotationAngle = self.initialAngle + newAngle
        
        if rotationAngle < -0.22 {
            rotationAngle = -0.22
        } else if rotationAngle > 3.0 {
            rotationAngle = 3.0
        }
        self.transform = CGAffineTransform(rotationAngle: rotationAngle)
        
        if gesture.state == .ended {
            self.initialAngle = rotationAngle
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
