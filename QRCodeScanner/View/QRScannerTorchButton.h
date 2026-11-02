//
//  QRScannerTorchButton.h
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 光线暗时出现的手电筒按钮，上面是图标，下面是文字
@interface QRScannerTorchButton : UIControl

/** 是否开启手电筒外观 */
@property (nonatomic, assign, getter=isTorchOn) BOOL torchOn;

@end

NS_ASSUME_NONNULL_END
