import 'package:get/get.dart';
import '../controllers/id_card_merge_controller.dart';

class IdCardMergeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<IdCardMergeController>(() => IdCardMergeController());
  }
}
