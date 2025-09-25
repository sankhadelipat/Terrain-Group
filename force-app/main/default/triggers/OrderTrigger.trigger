trigger OrderTrigger on Order (after update) {
    system.debug('running trigger OrderTrigger');
    if (Trigger.isAfter && Trigger.isUpdate) {
        // Only call sync if not in recursion and we have records
        //if (!FieldSyncHandler.isOrderSyncExecuting && !Trigger.new.isEmpty()) {
           // FieldSyncHandler.syncOrderToQuote(Trigger.newMap, Trigger.oldMap);
        //}
    }
}