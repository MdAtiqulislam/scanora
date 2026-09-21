enum ScanFilterType {
  original,
  color,
  smart,
  gray,
  blackAndWhite,
  // Legacy editor names retained for persistence compatibility.
  auto,
  magic,
}

enum CaptureSource { nativeScanner, camera, gallery }

enum ProcessingStage {
  decode,
  orientationNormalization,
  quadValidation,
  perspectiveTransform,
  illuminationNormalization,
  shadowReduction,
  backgroundNormalization,
  colorEnhancement,
  textEnhancement,
  adaptiveBinarization,
  render,
}

enum DocumentType { document, idCard, passport }
