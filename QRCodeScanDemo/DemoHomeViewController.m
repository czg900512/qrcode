//
//  DemoHomeViewController.m
//  QRCodeScanDemo
//
//  Created by czg on 2026/11/02.
//

#import "DemoHomeViewController.h"
#import "QRCodeScannerViewController.h"

@interface DemoHomeViewController ()

/** 打开扫描页 */
@property (nonatomic, strong) UIButton *scanButton;
/** 最近一次识别到的原文 */
@property (nonatomic, strong) UITextView *resultTextView;

@end

@implementation DemoHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"二维码扫描";
    [self.view addSubview:self.scanButton];
    [self.view addSubview:self.resultTextView];
    self.scanButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.resultTextView.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scanButton.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:32.f],
        [self.scanButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.scanButton.widthAnchor constraintEqualToConstant:180.f],
        [self.scanButton.heightAnchor constraintEqualToConstant:48.f],

        [self.resultTextView.topAnchor constraintEqualToAnchor:self.scanButton.bottomAnchor constant:24.f],
        [self.resultTextView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:20.f],
        [self.resultTextView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-20.f],
        [self.resultTextView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-20.f],
    ]];
}

- (void)openScanner {
    QRCodeScannerViewController *scanner = [[QRCodeScannerViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    scanner.onCodeRecognized = ^(QRCodeScannerViewController *scannerController, NSString *codeString) {
        DemoHomeViewController *strongSelf = weakSelf;
        strongSelf.resultTextView.text = codeString.length ? codeString : @"(空内容)";
        [scannerController.navigationController popViewControllerAnimated:YES];
    };
    [self.navigationController pushViewController:scanner animated:YES];
}

#pragma mark - Getters

- (UIButton *)scanButton {
    return _scanButton ?: (_scanButton = ({
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:@"开始扫描" forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:17.f weight:UIFontWeightSemibold];
        button.backgroundColor = [UIColor colorWithRed:1.f green:0.35f blue:0.14f alpha:1.f];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.layer.cornerRadius = 24.f;
        [button addTarget:self action:@selector(openScanner) forControlEvents:UIControlEventTouchUpInside];
        button;
    }));
}

- (UITextView *)resultTextView {
    return _resultTextView ?: (_resultTextView = ({
        UITextView *textView = [[UITextView alloc] init];
        textView.editable = NO;
        textView.selectable = YES;
        textView.font = [UIFont systemFontOfSize:16.f];
        textView.textColor = [UIColor labelColor];
        textView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        textView.layer.cornerRadius = 12.f;
        textView.textContainerInset = UIEdgeInsetsMake(16.f, 12.f, 16.f, 12.f);
        textView.text = @"识别结果会显示在这里。\n\n对准二维码或条码即可自动识别。画面里有多个码时，点箭头选择其中一个。也可以用右下角相册从图片识别。";
        textView;
    }));
}

@end
