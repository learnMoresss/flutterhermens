/// 检测助手消息是否包含待审批的危险操作提示
final approvalPattern = RegExp(
  r'⚠️.*危险|requires? (your )?approval|\/approve.*\/deny|do you want (me )?to (proceed|continue|run|execute)|需要.*批准|是否.*继续|是否.*执行',
  caseSensitive: false,
);

bool messageNeedsApproval(String text) => approvalPattern.hasMatch(text);
