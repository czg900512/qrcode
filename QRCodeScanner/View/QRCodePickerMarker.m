//
//  QRCodePickerMarker.m
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import "QRCodePickerMarker.h"

@interface QRCodePickerMarker ()

/** 码位箭头 */
@property (nonatomic, strong) UIImageView *iconImageView;

@end

@implementation QRCodePickerMarker

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupChildViews];
        [self layoutChildViews];
        [self setupAnimation];
    }
    return self;
}

- (void)setupChildViews {
    [self addSubview:self.iconImageView];
}

- (void)layoutChildViews {
    self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *width = [self.iconImageView.widthAnchor constraintEqualToConstant:44.f];
    NSLayoutConstraint *height = [self.iconImageView.heightAnchor constraintEqualToConstant:44.f];
    // 码框小于箭头时缩小箭头，避免箭头画出码外
    width.priority = 500;
    height.priority = 500;
    [NSLayoutConstraint activateConstraints:@[
        [self.iconImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.iconImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.iconImageView.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor],
        [self.iconImageView.heightAnchor constraintLessThanOrEqualToAnchor:self.heightAnchor],
        width,
        height,
    ]];
}

/// 轻微缩放，提示该位置可以点
- (void)setupAnimation {
    CABasicAnimation *scaleAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scaleAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    scaleAnimation.fromValue = @(1.f);
    scaleAnimation.toValue = @(1.1f);
    scaleAnimation.duration = .8f;
    scaleAnimation.autoreverses = YES;
    scaleAnimation.repeatCount = 2;

    CAAnimationGroup *groupAnimation = [CAAnimationGroup animation];
    groupAnimation.animations = @[scaleAnimation];
    groupAnimation.duration = 5.f;
    groupAnimation.repeatCount = CGFLOAT_MAX;

    [self.iconImageView.layer addAnimation:groupAnimation forKey:@"scaleAnimation"];
}

#pragma mark - Getters

- (UIImageView *)iconImageView {
    return _iconImageView ?: (_iconImageView = ({
        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.image = [UIImage imageNamed:@"qrcode_scanner_mark"];
        imageView;
    }));
}

@end
