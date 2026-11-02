# 二维码扫描

iOS 二维码与条形码扫描示例。支持相机实时扫描、自动拉近、暗光手电筒、多个码点选，以及从相册图片识别二维码。

本仓库可以单独运行。打开应用后进入扫描页，用后置相机识别二维码和常见条形码，识别结果会回到首页展示。

## 功能

- 相机实时扫描二维码，以及 Code 128、EAN、Code 39、Code 93 等常见条形码
- 码比较小时自动拉近，并保持对焦
- 光线较暗时出现手电筒，可手动开关
- 画面里同时出现多个码时，点对应箭头选择其中一个
- 从相册选择图片，识别图片中的二维码
- 支持竖屏和横屏，手机会随方向调整相机画面

扫描能力放在 `QRCodeScanner` 中，不包含具体业务跳转。识别成功后通过回调把码里的文字交给调用方。`QRCodeScanDemo` 只负责打开扫描页并展示结果。

## 运行

用 Xcode 打开 `QRCodeScanDemo.xcodeproj`，选择 scheme `QRCodeScanDemo` 后运行。

- 系统要求：iOS 14.0 及以上
- 实时扫码需要真机。模拟器没有相机，可以用相册识图验证
- 首次使用会申请相机和相册权限

## 目录

| 目录 | 作用 |
|---|---|
| `QRCodeScanner/Interface` | 扫描页 `QRCodeScannerViewController` |
| `QRCodeScanner/Camera` | 预览坐标、手机朝向和相机方向的对应 |
| `QRCodeScanner/Recognition` | 找二维码位置、安排搜索区域、记录扫描状态 |
| `QRCodeScanner/View` | 手电筒、多个码时的点选 |
| `QRCodeScanner/Support` | 不抓住页面的定时器 |
| `QRCodeScanDemo` | 演示首页 |

## 接入

把 `QRCodeScanner` 目录加进自己的工程，在需要打开扫描页的地方：

```objc
#import "QRCodeScannerViewController.h"

QRCodeScannerViewController *scanner = [[QRCodeScannerViewController alloc] init];
scanner.onCodeRecognized = ^(QRCodeScannerViewController *scanner, NSString *codeString) {
    // codeString 是识别出的内容。此时相机已停止。
    [scanner.navigationController popViewControllerAnimated:YES];
};
[self.navigationController pushViewController:scanner animated:YES];
```

回调在主线程执行。调用方可以关闭页面，也可以调用 `resumeScanning` 继续扫描。不设置回调时，扫描页会自己弹出识别内容，并允许继续扫描。

工程需要开启相机和相册权限说明：

- `NSCameraUsageDescription`：需要使用相机扫描二维码和条形码
- `NSPhotoLibraryUsageDescription`：需要访问相册，从图片中识别二维码

