//
//  QRScannerTorchButton.m
//  QRCodeScanner
//
//  Created by czg on 2026/11/02.
//

#import "QRScannerTorchButton.h"

@interface QRScannerTorchButton ()

/** 手电筒图标 */
@property (nonatomic, strong) UIImageView *iconImageView;
/** 「轻触照亮 / 轻触关闭」文案 */
@property (nonatomic, strong) UILabel *titleLabel;

@end

@implementation QRScannerTorchButton

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupChildViews];
        [self layoutChildViews];
        [self updateAppearance];
    }
    return self;
}

- (void)setupChildViews {
    [self addSubview:self.iconImageView];
    [self addSubview:self.titleLabel];
}

- (void)layoutChildViews {
    self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.iconImageView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.iconImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.iconImageView.widthAnchor constraintEqualToConstant:40.f],
        [self.iconImageView.heightAnchor constraintEqualToConstant:40.f],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.iconImageView.bottomAnchor constant:5.f],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)setTorchOn:(BOOL)torchOn {
    if (_torchOn == torchOn) {
        return;
    }
    _torchOn = torchOn;
    [self updateAppearance];
}

- (void)updateAppearance {
    if (self.isTorchOn) {
        self.iconImageView.image = [UIImage imageNamed:@"ligopen"];
        self.titleLabel.text = @"轻触关闭";
    } else {
        self.iconImageView.image = [UIImage imageNamed:@"ligclose"];
        self.titleLabel.text = @"轻触照亮";
    }
}

#pragma mark - Getters

- (UIImageView *)iconImageView {
    return _iconImageView ?: (_iconImageView = ({
        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        imageView.userInteractionEnabled = NO;
        imageView;
    }));
}

- (UILabel *)titleLabel {
    return _titleLabel ?: (_titleLabel = ({
        UILabel *label = [[UILabel alloc] init];
        label.font = [UIFont systemFontOfSize:12.f];
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.userInteractionEnabled = NO;
        label;
    }));
}

@end
