public class FieldSyncHandler {
    // Static variables to prevent recursion
    public static Boolean isOrderSyncExecuting = false;
    public static Boolean isQuoteSyncExecuting = false;
    public static Set<Id> processedOrderIds = new Set<Id>();
    public static Set<Id> processedQuoteIds = new Set<Id>();
    
    // Sync from Order (child) to Quote (parent)
    public static void syncOrderToQuote(Map<Id, Order> newMap, Map<Id, Order> oldMap) {
        system.debug('running syncOrderToQuote');
        // Prevent recursion
        if (isOrderSyncExecuting) return;
        isOrderSyncExecuting = true;
        system.debug('running syncOrderToQuote after isOrderSyncExecuting');
        
        try {
            Set<Id> quoteIds = new Set<Id>();
            Map<Id, Order> ordersWithChanges = new Map<Id, Order>();
            integer icount = 0;
            for (Order ord : newMap.values()) {
                system.debug('Order loop count '+ icount++);
                Order oldOrd = oldMap.get(ord.Id);
                
                // Skip if already processed in this transaction
                if (processedOrderIds.contains(ord.Id)) continue;
                system.debug('line inside loop after - processedOrderIds');
                
                // Check if either field changed and QuoteId exists
                if (fieldsChanged(ord, oldOrd) && ord.Parent_Quote__c != null) {
                    quoteIds.add(ord.Parent_Quote__c);
                    ordersWithChanges.put(ord.Parent_Quote__c, ord);
                    processedOrderIds.add(ord.Id);
                    System.debug('Order ' + ord.Id + ' triggered sync to Quote ' + ord.Parent_Quote__c);
                }
            }
            
            if (!quoteIds.isEmpty()) {
                updateQuotesFromOrders(quoteIds, ordersWithChanges);
            }
        } catch (Exception e) {
            // Log errors but don't throw to avoid blocking original transaction
            System.debug('Error in syncOrderToQuote: ' + e.getMessage() + ' - ' + e.getStackTraceString());
        } finally {
            // Reset flag in finally block to ensure it always runs
            isOrderSyncExecuting = false;
        }
    }
    
    // Sync from Quote (parent) to all related Orders (children)
    public static void syncQuoteToOrder(Map<Id, Quote> newMap, Map<Id, Quote> oldMap) {
        system.debug('running syncQuoteToOrder');
        // Prevent recursion
        if (isQuoteSyncExecuting) return;
        isQuoteSyncExecuting = true;
        system.debug('running syncQuoteToOrder after isQuoteSyncExecuting');
        
        try {
            Set<Id> quoteIdsWithChanges = new Set<Id>();
            Map<Id, Quote> changedQuotesMap = new Map<Id, Quote>();
            
            for (Quote qt : newMap.values()) {
                Quote oldQt = oldMap.get(qt.Id);
                
                // Skip if already processed in this transaction
                if (processedQuoteIds.contains(qt.Id)) continue;
                
                // Check if either field changed
                if (fieldsChanged(qt, oldQt)) {
                    quoteIdsWithChanges.add(qt.Id);
                    changedQuotesMap.put(qt.Id, qt);
                    processedQuoteIds.add(qt.Id);
                    System.debug('Quote ' + qt.Id + ' triggered sync to related Orders');
                }
            }
            
            if (!quoteIdsWithChanges.isEmpty()) {
                updateOrdersFromQuotes(quoteIdsWithChanges, changedQuotesMap);
            }
        } catch (Exception e) {
            // Log errors but don't throw to avoid blocking original transaction
            System.debug('Error in syncQuoteToOrder: ' + e.getMessage() + ' - ' + e.getStackTraceString());
        } finally {
            // Reset flag in finally block to ensure it always runs
            isQuoteSyncExecuting = false;
        }
    }
    
    // Check if any of the synchronized fields changed
    private static Boolean fieldsChanged(SObject newObj, SObject oldObj) {
        return newObj.get('Date_Approved__c') != oldObj.get('Date_Approved__c') ||
               newObj.get('Date_Issued__c') != oldObj.get('Date_Issued__c');
    }
    
    // Update Quote from Order (child to parent - one-to-one)
    private static void updateQuotesFromOrders(Set<Id> quoteIds, Map<Id, Order> ordersMap) {
        system.debug('running updateQuotesFromOrders ');
        List<Quote> quotesToUpdate = new List<Quote>();
        
        for (Quote qt : [SELECT Id, Date_Approved__c, Date_Issued__c 
                         FROM Quote 
                         WHERE Id IN :quoteIds]) {
            
            Order relatedOrder = ordersMap.get(qt.Id);
            Boolean needsUpdate = false;
            
            // Only update if values are different
            if (qt.Date_Approved__c != relatedOrder.Date_Approved__c) {
                qt.Date_Approved__c = relatedOrder.Date_Approved__c;
                needsUpdate = true;
            }
            if (qt.Date_Issued__c != relatedOrder.Date_Issued__c) {
                qt.Date_Issued__c = relatedOrder.Date_Issued__c;
                needsUpdate = true;
            }
            
            if (needsUpdate) {
                quotesToUpdate.add(qt);
            }
        }
        
        if (!quotesToUpdate.isEmpty()) {
            // Use partial success to avoid failing entire batch if one record fails
            Database.SaveResult[] results = Database.update(quotesToUpdate, false);
            logSaveResults(results, 'Quote');
        }
    }
    
    // Update all Orders from Quote (parent to children - one-to-many)
    private static void updateOrdersFromQuotes(Set<Id> quoteIds, Map<Id, Quote> quotesMap) {
        system.debug('running updateOrdersFromQuotes ');
        List<Order> ordersToUpdate = new List<Order>();
        
        // Get all orders related to the changed quotes
        for (Order ord : [SELECT Id, Parent_Quote__c, Date_Approved__c, Date_Issued__c 
                          FROM Order 
                          WHERE Parent_Quote__c IN :quoteIds]) {
            
            Quote relatedQuote = quotesMap.get(ord.Parent_Quote__c);
            Boolean needsUpdate = false;
            
            // Only update if values are different
            if (ord.Date_Approved__c != relatedQuote.Date_Approved__c) {
                ord.Date_Approved__c = relatedQuote.Date_Approved__c;
                needsUpdate = true;
            }
            if (ord.Date_Issued__c != relatedQuote.Date_Issued__c) {
                ord.Date_Issued__c = relatedQuote.Date_Issued__c;
                needsUpdate = true;
            }
            
            if (needsUpdate) {
                ordersToUpdate.add(ord);
            }
        }
        
        if (!ordersToUpdate.isEmpty()) {
            // Use partial success to avoid failing entire batch if one record fails
            Database.SaveResult[] results = Database.update(ordersToUpdate, false);
            logSaveResults(results, 'Order');
        }
    }
    
    // Helper method to log save results
    private static void logSaveResults(Database.SaveResult[] results, String objectType) {
        system.debug('running logSaveResults ');
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                System.debug('Error updating ' + objectType + ' record: ' + sr.getErrors()[0].getMessage());
            }
        }
    }
}