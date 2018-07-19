//
//  CustomButtons.swift
//  SoundTest5
//
//  Created by Sebastian Reinolds on 18/07/2018.
//  Copyright © 2018 Sebastian Reinolds. All rights reserved.
//

import UIKit

class waveButton: UIButton {
    var waveform: waveform_type
    
    init(waveform: waveform_type) {
        self.waveform = waveform
        super.init(frame: .zero)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class filterButton: UIButton {
    var filter: filter_type
    
    init(filter: filter_type) {
        self.filter = filter
        super.init(frame: .zero)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
