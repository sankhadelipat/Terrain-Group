trigger QuoteTrigger on Quote (after update) {
    system.debug('running trigger QuoteTrigger');
    if (Trigger.isAfter && Trigger.isUpdate) {
        // Only call sync if not in recursion and we have records
        //if (!FieldSyncHandler.isQuoteSyncExecuting && !Trigger.new.isEmpty()) {
           // FieldSyncHandler.syncQuoteToOrder(Trigger.newMap, Trigger.oldMap);
        //}
    }
}