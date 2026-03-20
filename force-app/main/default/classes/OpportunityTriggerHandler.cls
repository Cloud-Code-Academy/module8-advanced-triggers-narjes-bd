public with sharing class OpportunityTriggerHandler extends TriggerHandler {

     
    /* 
    * When an opportunity is updated validate that the amount is greater than 5000.
    * Trigger should only fire on update.
    */
    public override void beforeUpdate() {
        for(Opportunity opp : (List<Opportunity>) Trigger.new){
            if(opp.Amount < 5000){
                opp.addError('Opportunity amount must be greater than 5000');
            }
        }
         /*
    
        * When an opportunity is updated set the primary contact on the opportunity to the contact with the title of 'CEO'.
        * Trigger should only fire on update.
        */
    
        //Get contacts related to the opportunity account
        Set<Id> accountIds = new Set<Id>();
        for(Opportunity opp : (List<Opportunity>) Trigger.new){
            accountIds.add(opp.AccountId);
        }
        
        Map<Id, Contact> contacts = new Map<Id, Contact>([SELECT Id, FirstName, AccountId FROM Contact WHERE AccountId IN :accountIds AND Title = 'CEO' ORDER BY FirstName ASC]);
        Map<Id, Contact> accountIdToContact = new Map<Id, Contact>();

        for (Contact cont : contacts.values()) {
            if (!accountIdToContact.containsKey(cont.AccountId)) {
                accountIdToContact.put(cont.AccountId, cont);
            }
        }

        for(Opportunity opp : (List<Opportunity>) Trigger.new){
            if(opp.Primary_Contact__c == null){
                if (accountIdToContact.containsKey(opp.AccountId)){
                    opp.Primary_Contact__c = accountIdToContact.get(opp.AccountId).Id;
                }
            }
        }

         // Append Stage changes in Opportunity Description
         for (Opportunity opp : (List<Opportunity>) Trigger.new){
            Opportunity oldOpp = (Opportunity) Trigger.oldMap.get(opp.Id);
            if (opp.StageName != oldOpp.StageName){
                opp.Description += '\n Stage Change:' + opp.StageName + ':' + DateTime.now().format();
            }
        }
    } 
       

    /*
    
    * When an opportunity is deleted prevent the deletion of a closed won opportunity if the account industry is 'Banking'.
    * Trigger should only fire on delete.
    */
    public override void beforeDelete() {
        //Account related to the opportunities 
        Map<Id, Account> accounts = new Map<Id, Account>([SELECT Id, Industry FROM Account WHERE Id IN (SELECT AccountId FROM Opportunity WHERE Id IN :Trigger.old)]);
        for(Opportunity opp : (List<Opportunity>) Trigger.old){
            if(opp.StageName == 'Closed Won'){
                if(accounts.get(opp.AccountId).Industry == 'Banking'){
                    opp.addError('Cannot delete a closed won opportunity for a banking account');
                }
            }
        }

        for (Opportunity oldOpp : (List<Opportunity>) Trigger.old) {
            if (oldOpp.IsClosed) {
                oldOpp.addError('Cannot delete closed opportunity');
            }
        }
    }
    

    public override void beforeInsert() {
        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            if (opp.Type == null) {
                opp.Type = 'New Customer';
            }
        }
    }

  

    public override void afterInsert() {
        // Create a new Task for newly inserted Opportunities
        List<Task> tasksToInsert = new List<Task>();
        for (Opportunity opp : (List<Opportunity>) Trigger.new){
            Task tsk = new Task();
            tsk.Subject = 'Call Primary Contact';
            tsk.WhatId = opp.Id;
            tsk.WhoId = opp.Primary_Contact__c;
            tsk.OwnerId = opp.OwnerId;
            tsk.ActivityDate = Date.today().addDays(3);
            tasksToInsert.add(tsk);
        }
        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }

       
    public override void afterDelete() {      
        
        // Send email notifications when an Opportunity is deleted 
        notifyOwnersOpportunityDeleted(Trigger.old);
        
    } 

    public override void afterUndelete() {   
        // Assign the primary contact to undeleted Opportunities
            assignPrimaryContact((Map<Id, Opportunity>) Trigger.newMap);
    }
    

    /*
    notifyOwnersOpportunityDeleted:
    - Sends an email notification to the owner of the Opportunity when it gets deleted.
    - Uses Salesforce's Messaging.SingleEmailMessage to send the email.
    */
    private static void notifyOwnersOpportunityDeleted(List<Opportunity> opps) {
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        Set<Id> ownerIds = new Set<Id>();
        for (Opportunity opp : opps) {
            if (opp.OwnerId != null) {
                ownerIds.add(opp.OwnerId);
            }
        }

        Map<Id, User> usersById = new Map<Id, User>(
        [SELECT Id, Email FROM User WHERE Id IN :ownerIds]);

        for (Opportunity opp : opps){
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            //String[] toAddresses = new String[] {[SELECT Id, Email FROM User WHERE Id = :opp.OwnerId].Email};
            User owner = usersById.get(opp.OwnerId);
            String[] toAddresses = new String[] {owner.Email};
            mail.setToAddresses(toAddresses);
            mail.setSubject('Opportunity Deleted : ' + opp.Name);
            mail.setPlainTextBody('Your Opportunity: ' + opp.Name +' has been deleted.');
            mails.add(mail);
        }        
        
        try {
            Messaging.sendEmail(mails);
        } catch (Exception e){
            System.debug('Exception: ' + e.getMessage());
        }
    }

    /*
    assignPrimaryContact:
    - Assigns a primary contact with the title of 'VP Sales' to undeleted Opportunities.
    - Only updates the Opportunities that don't already have a primary contact.
    */
    private static void assignPrimaryContact(Map<Id,Opportunity> oppNewMap) {        
        //Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>();
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : oppNewMap.values()) {
            if (opp.AccountId != null && opp.Primary_Contact__c == null) {
                accountIds.add(opp.AccountId);
            }
        }

        Map<Id, Contact> primaryContactByAccountId = new Map<Id, Contact>(); 

        for (Contact con : [SELECT Id, AccountId FROM Contact WHERE Title = 'VP Sales' AND AccountId IN :accountIds]) {
            if (!primaryContactByAccountId.containsKey(con.AccountId)) {
                primaryContactByAccountId.put(con.AccountId, con);
        }
        }
        List<Opportunity> oppsToUpdate = new List<Opportunity>();
       
        for (Opportunity opp : oppNewMap.values()){            
            //Contact primaryContact = [SELECT Id, AccountId FROM Contact WHERE Title = 'VP Sales' AND AccountId = :opp.AccountId LIMIT 1];
            if (opp.Primary_Contact__c == null){
                Contact primaryContact = primaryContactByAccountId.get(opp.AccountId);
                Opportunity oppToUpdate = new Opportunity(Id = opp.Id);
                oppToUpdate.Primary_Contact__c = primaryContact.Id;
                oppsToUpdate.add(oppToUpdate);
            }
        }
        //update oppMap.values();
        if (!oppsToUpdate.isEmpty()) {
            update oppsToUpdate;
        }
    }
}



