//
//  QRCodeScannerViewController.h
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class QRCodeScannerViewController;

/**
 识别出一条内容后的回调。

 @param scanner 当前扫描页
 @param codeString 码里的文字。相机可以识别二维码和条形码，相册目前只识别二维码
 @discussion 在主线程回调。这时相机已经停了。调用方可以关掉页面，或者调用 `resumeScanning` 继续扫。
 */
typedef void (^QRCodeScannerResultHandler)(QRCodeScannerViewController *scanner, NSString *codeString);

/// 扫描页。打开相机、暗处手电、自动拉近、多个码时点选，也可以从相册识图
@interface QRCodeScannerViewController : UIViewController

/** 识别成功后的回调。不设置时，页面自己弹窗显示内容，并可以继续扫描 */
@property (nonatomic, copy, nullable) QRCodeScannerResultHandler onCodeRecognized;

/** 重新开始扫描。页面还显示在屏幕上时才有效 */
- (void)resumeScanning;

@end

NS_ASSUME_NONNULL_END
