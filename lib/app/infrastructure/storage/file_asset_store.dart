import 'file_system_asset_store.dart';

/// Compatibility name retained for existing M01 callers.
class FileAssetStore extends FileSystemAssetStore {
  FileAssetStore(super.root);
}
