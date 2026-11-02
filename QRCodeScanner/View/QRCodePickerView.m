//
//  QRCodePickerView.m
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import "QRCodePickerView.h"
#import "QRCodePickerMarker.h"
#import <AVFoundation/AVFoundation.h>

static const NSInteger kQRCodePickerMarkerTagBase = 1000;

@interface QRCodePickerView ()

/** 关闭选择器 */
@property (nonatomic, strong) UIButton *closeButton;
/** 相册模式下的模糊底图 */
@property (nonatomic, strong) UIImageView *bgImageView;
/** 相册模式下居中的清晰图片，箭头加在这层上 */
@property (nonatomic, strong) UIImageView *imageView;
/** 底部「点击箭头，选择二维码」提示 */
@property (nonatomic, strong) UIImageView *markImageView;
/** 清晰图片宽度，按原图比例更新 */
@property (nonatomic, strong) NSLayoutConstraint *imageWidthConstraint;
/** 清晰图片高度，按原图比例更新 */
@property (nonatomic, strong) NSLayoutConstraint *imageHeightConstraint;

@end

@implementation QRCodePickerView

- (void)setupChildViews {
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.2f];
    [self removeOwnSubviews];

    if (self.cameraCodes.count) {
        [self placeMarkersOnCamera];
    } else if (self.imageFeatures.count) {
        self.imageView.image = self.image;
        self.bgImageView.image = self.image;
        [self addSubview:self.bgImageView];
        self.bgImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [self.bgImageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.bgImageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.bgImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.bgImageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
        [self placeMarkersOnImage];
    }

    [self addSubview:self.closeButton];
    [self addSubview:self.markImageView];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.markImageView.translatesAutoresizingMaskIntoConstraints = NO;
    CGFloat bottomGap = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? 60.f : 30.f;
    [NSLayoutConstraint activateConstraints:@[
        [self.closeButton.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:10.f],
        [self.closeButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.f],
        [self.closeButton.widthAnchor constraintEqualToConstant:44.f],
        [self.closeButton.heightAnchor constraintEqualToConstant:44.f],

        [self.markImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.markImageView.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-bottomGap],
        [self.markImageView.widthAnchor constraintEqualToConstant:133.f],
        [self.markImageView.heightAnchor constraintEqualToConstant:22.f],
    ]];
}

/// 实时扫码的码框已经在预览坐标系，换算到选择器后再放箭头
- (void)placeMarkersOnCamera {
    for (NSInteger i = 0; i < (NSInteger)self.cameraCodes.count; ++i) {
        id object = [self objectAtIndex:(NSUInteger)i inArray:self.cameraCodes];
        if (![object isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) {
            continue;
        }
        AVMetadataMachineReadableCodeObject *metadataObject = object;
        CGRect markFrame = metadataObject.bounds;
        AVCaptureVideoPreviewLayer *previewLayer = self.sourcePreviewLayer;
        if (previewLayer) {
            markFrame = [previewLayer convertRect:metadataObject.bounds toLayer:self.layer];
        }
        QRCodePickerMarker *markControl = [[QRCodePickerMarker alloc] initWithFrame:markFrame];
        markControl.tag = kQRCodePickerMarkerTagBase + i;
        [markControl addTarget:self action:@selector(markerButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:markControl];
    }
}

/// 相册图片按屏幕可用区域等比缩放后，把 CoreImage 底边原点的框翻转到 UIKit 坐标
- (void)placeMarkersOnImage {
    [self removeSubviewsFromView:self.imageView];

    CGFloat canvasWidth = CGRectGetWidth(self.bounds);
    CGFloat canvasHeight = CGRectGetHeight(self.bounds);
    if (canvasWidth < 1.f || canvasHeight < 1.f) {
        canvasWidth = CGRectGetWidth(UIScreen.mainScreen.bounds);
        canvasHeight = CGRectGetHeight(UIScreen.mainScreen.bounds);
    }
    BOOL isPad = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
    CGFloat topHeight = self.safeAreaInsets.top + 44.f;
    CGFloat bottomSafe = self.safeAreaInsets.bottom;
    CGSize imageSize = CGSizeMake(canvasWidth, canvasHeight - topHeight - bottomSafe - (isPad ? 90.f : 60.f));
    if (imageSize.height < 1.f) {
        imageSize.height = 1.f;
    }

    if (self.image && (self.image.size.width / self.image.size.height) > (imageSize.width / imageSize.height)) {
        imageSize.height = imageSize.width * (self.image.size.height / self.image.size.width);
    } else if (self.image && (self.image.size.width / self.image.size.height) < (imageSize.width / imageSize.height)) {
        imageSize.width = imageSize.height * (self.image.size.width / self.image.size.height);
    }

    if (!self.imageWidthConstraint) {
        self.imageWidthConstraint = [self.imageView.widthAnchor constraintEqualToConstant:imageSize.width];
        self.imageHeightConstraint = [self.imageView.heightAnchor constraintEqualToConstant:imageSize.height];
        [NSLayoutConstraint activateConstraints:@[self.imageWidthConstraint, self.imageHeightConstraint]];
    } else {
        self.imageWidthConstraint.constant = imageSize.width;
        self.imageHeightConstraint.constant = imageSize.height;
    }

    CGFloat scale = self.image.size.width > 0.f ? (imageSize.width / self.image.size.width) : 1.f;
    for (NSInteger i = 0; i < (NSInteger)self.imageFeatures.count; ++i) {
        id object = [self objectAtIndex:(NSUInteger)i inArray:self.imageFeatures];
        if (![object isKindOfClass:[CIQRCodeFeature class]]) {
            continue;
        }
        CIQRCodeFeature *feature = object;
        CGAffineTransform transform = CGAffineTransformMakeScale(1, -1);
        transform = CGAffineTransformTranslate(transform, 0, -self.image.size.height);
        CGRect fixedFrame = CGRectApplyAffineTransform(feature.bounds, transform);
        CGRect featureFrame = CGRectMake(fixedFrame.origin.x * scale,
                                         fixedFrame.origin.y * scale,
                                         fixedFrame.size.width * scale,
                                         fixedFrame.size.height * scale);
        QRCodePickerMarker *markControl = [[QRCodePickerMarker alloc] initWithFrame:featureFrame];
        markControl.tag = kQRCodePickerMarkerTagBase + i;
        [markControl addTarget:self action:@selector(markerButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.imageView addSubview:markControl];
    }
}

- (void)showInView:(UIView *)view {
    if (!view || ![view isKindOfClass:[UIView class]]) {
        return;
    }
    [self removeFromSuperview];
    [view addSubview:self];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.topAnchor constraintEqualToAnchor:view.topAnchor],
        [self.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [self.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [self.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
    ]];
    [view layoutIfNeeded];
    [self setupChildViews];
}

- (void)dismiss {
    if ([self.delegate respondsToSelector:@selector(pickerViewDidClose:)]) {
        [self.delegate pickerViewDidClose:self];
    }
    [self removeFromSuperview];
}

#pragma mark - Target Action

- (void)closeButtonTapped:(UIButton *)sender {
    [self dismiss];
}

- (void)markerButtonTapped:(UIControl *)sender {
    if (![self.delegate respondsToSelector:@selector(pickerView:didSelectCode:)]) {
        return;
    }
    NSInteger index = sender.tag - kQRCodePickerMarkerTagBase;
    if (index < 0) {
        return;
    }
    NSString *stringValue = @"";
    if (self.cameraCodes.count) {
        id object = [self objectAtIndex:(NSUInteger)index inArray:self.cameraCodes];
        if ([object isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) {
            stringValue = [(AVMetadataMachineReadableCodeObject *)object stringValue];
        }
    } else {
        id object = [self objectAtIndex:(NSUInteger)index inArray:self.imageFeatures];
        if ([object isKindOfClass:[CIQRCodeFeature class]]) {
            stringValue = [(CIQRCodeFeature *)object messageString];
        }
    }
    [self removeFromSuperview];
    [self.delegate pickerView:self didSelectCode:stringValue];
}

#pragma mark - Private Methods

- (void)removeOwnSubviews {
    [self removeSubviewsFromView:self];
}

- (void)removeSubviewsFromView:(UIView *)view {
    for (UIView *subview in [view.subviews copy]) {
        [subview removeFromSuperview];
    }
}

- (id)objectAtIndex:(NSUInteger)index inArray:(NSArray *)array {
    if (index >= array.count) {
        return nil;
    }
    return array[index];
}

#pragma mark - Getters

- (UIButton *)closeButton {
    return _closeButton ?: (_closeButton = ({
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        [button setImage:[UIImage imageNamed:@"nav_back_round"] forState:UIControlStateNormal];
        button.accessibilityLabel = @"返回";
        [button addTarget:self action:@selector(closeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        button;
    }));
}

- (UIImageView *)bgImageView {
    return _bgImageView ?: (_bgImageView = ({
        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        imageView.userInteractionEnabled = YES;

        UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:effect];
        [imageView addSubview:effectView];
        [imageView addSubview:self.imageView];
        effectView.translatesAutoresizingMaskIntoConstraints = NO;
        self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [effectView.topAnchor constraintEqualToAnchor:imageView.topAnchor],
            [effectView.bottomAnchor constraintEqualToAnchor:imageView.bottomAnchor],
            [effectView.leadingAnchor constraintEqualToAnchor:imageView.leadingAnchor],
            [effectView.trailingAnchor constraintEqualToAnchor:imageView.trailingAnchor],
            [self.imageView.centerXAnchor constraintEqualToAnchor:imageView.centerXAnchor],
            [self.imageView.centerYAnchor constraintEqualToAnchor:imageView.centerYAnchor],
        ]];
        imageView;
    }));
}

- (UIImageView *)imageView {
    return _imageView ?: (_imageView = ({
        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.userInteractionEnabled = YES;
        imageView;
    }));
}

- (UIImageView *)markImageView {
    return _markImageView ?: (_markImageView = ({
        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.image = [UIImage imageNamed:@"qrcode_scanner_select_mark"];
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        imageView;
    }));
}

@end
