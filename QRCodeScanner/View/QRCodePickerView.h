//
//  QRCodePickerView.h
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import <UIKit/UIKit.h>

@class QRCodePickerView;
@class AVMetadataMachineReadableCodeObject;
@class AVCaptureVideoPreviewLayer;

NS_ASSUME_NONNULL_BEGIN

@protocol QRCodePickerViewDelegate <NSObject>

/** 点中了其中一个码，codeString 是这个码里的内容 */
- (void)pickerView:(QRCodePickerView *)pickerView didSelectCode:(NSString *)codeString;

/** 点了关闭，没有选择任何码 */
- (void)pickerViewDidClose:(QRCodePickerView *)pickerView;

@end

/// 画面里有多个二维码时，让用户点其中一个
@interface QRCodePickerView : UIView

/** 点选回调 */
@property (nonatomic, weak, nullable) id<QRCodePickerViewDelegate> delegate;

/** 相机实时扫到的码。和 imageFeatures 二选一 */
@property (nonatomic, copy, nullable) NSArray<AVMetadataMachineReadableCodeObject *> *cameraCodes;

/** 相机预览图层，用来把码的位置换到选择层上。从相册识别时不用传 */
@property (nonatomic, weak, nullable) AVCaptureVideoPreviewLayer *sourcePreviewLayer;

/** 从相册选出的图片 */
@property (nonatomic, strong, nullable) UIImage *image;

/** 相册图片里找到的二维码 */
@property (nonatomic, copy, nullable) NSArray *imageFeatures;

- (void)showInView:(UIView *)view;

- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
