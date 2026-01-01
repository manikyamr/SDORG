/**
* @description       : Handler class to handle trigger operations on ServiceAppointment object.
* @author            : sourav.das.adhikary@accenture.com
* @group             :
* @last modified on  : 01-24-2025
* @last modified by  : sourav.das.adhikary@accenture.com
**/
public with sharing class CS_ServiceAppointmentTriggerHandler {

    private static Map<String, String[]> concernTypeCategoryAndSubCategories;

    /**
* @description : method to handle work order creation
* @author: sourav.das.adhikary@accenture.com | 01-24-2025
* @param: serviceAppointmentList
* @return void
**/
    public static void handleWorkOrderCreation(List<ServiceAppointment> serviceAppointmentList, Map<Id, ServiceAppointment> oldServiceAppointmentMap) {
        // Check if the ServiceAppointment status has changed and the current status is 'Checked'
        System.debug('serviceAppointmentList====>' + serviceAppointmentList);

        List<Case> caseList = new List<Case>();
        List<Id> parentWOIds = new List<Id>();
        List<WorkOrder> workOrdersToClone = new List<WorkOrder>();
        Set<Id> caseIds = new Set<Id>();
        Map<Id, Id[]> parentRecordIdToServiceAppointments = new Map<Id, Id[]>();
        Map<Id, Id> caseToSAMap = new Map<Id, Id>();
        Map<Id, Boolean> parentROIdToTireAccFlagMap = new Map<Id, Boolean>();
        Set<Id> parentROIds = new Set<Id>();
        for (ServiceAppointment sa : serviceAppointmentList) {
            if (sa.CS_WorkOrder__c != null) {
                parentROIds.add(sa.CS_WorkOrder__c);
            }
        }
        if (!parentROIds.isEmpty()) {
            for (WorkOrder wo : [
                SELECT Id, CS_IsTireOrAccRO__c
                FROM WorkOrder
                WHERE Id IN :parentROIds
                WITH USER_MODE
            ]) {
                parentROIdToTireAccFlagMap.put(wo.Id, wo.CS_IsTireOrAccRO__c);
            }
        }
        system.debug('parentROIdToTireAccFlagMap====>' + parentROIdToTireAccFlagMap);

        // For Vehicle Pickup logic
        List<Id> vehiclePickupWOIds = new List<Id>();
        Map<Id, Id> workOrderToCaseMap = new Map<Id, Id>();

        for (ServiceAppointment sa : serviceAppointmentList) {
            if (
                oldServiceAppointmentMap != null &&
                oldServiceAppointmentMap.containsKey(sa.Id) &&
                sa.Status != oldServiceAppointmentMap.get(sa.Id).Status &&
                sa.Status == CS_Constants.CS_CHECKEDINSTATUS &&
                oldServiceAppointmentMap.get(sa.Id).ParentRecordId != null &&
                oldServiceAppointmentMap.get(sa.Id).CS_Case__c != null
            ) {
                system.debug('sa.AppointmentType Main---'+sa.AppointmentType);
                system.debug('sa.AppointmentType map---'+parentROIdToTireAccFlagMap);
                system.debug('sa.AppointmentType get---'+parentROIdToTireAccFlagMap.get(sa.CS_WorkOrder__c));
                system.debug('sa.AppointmentType get---'+sa.AppointmentType == CS_Constants.CS_REVISIT);
                if (sa.AppointmentType == CS_Constants.CS_REVISIT ||
                    sa.AppointmentType == CS_Constants.CS_CPOREVISITAPPTTYPE ||
                    (parentROIdToTireAccFlagMap.containsKey(sa.CS_WorkOrder__c) && parentROIdToTireAccFlagMap.get(sa.CS_WorkOrder__c))) {
                    parentWOIds.add(sa.CS_WorkOrder__c);
                    caseToSAMap.put(sa.ParentRecordId, sa.Id);
                } else {
                    Id key = oldServiceAppointmentMap.get(sa.Id).ParentRecordId;
                    caseIds.add(key);
                    Id[] serviceAppointmentIds = parentRecordIdToServiceAppointments.get(key);
                    if (serviceAppointmentIds == null) {
                        serviceAppointmentIds = new Id[]{};
                        parentRecordIdToServiceAppointments.put(key, serviceAppointmentIds);
                    }
                    serviceAppointmentIds.add(sa.Id);
                }
            }


            //Move Vehicle Pickup check here — inside the loop
            if (sa.AppointmentType == CS_Constants.CS_VEHICLEPICKUP && sa.CS_WorkOrder__c != null && sa.CS_Case__c != null) {
                vehiclePickupWOIds.add(sa.CS_WorkOrder__c);
                workOrderToCaseMap.put(sa.CS_WorkOrder__c, sa.CS_Case__c);
            }

        }

        if (!parentWOIds.isEmpty()) {
            for (WorkOrder wo : [
                SELECT Id, CaseId, ContactId, AccountId, CS_Vehicle__c, CS_RepairPartnerFacility__c,
                    CS_RepairPartnerServiceAdvisor__c, CS_ContactEmail__c, CS_ContactMobile__c, Subject,
                    Priority, OwnerId, CS_ServiceType__c, CS_INSCompanyName__c, CS_INSPolicyNumber__c,
                    CS_INSContactNumber__c, CS_PreferredMethodOfContact__c, CS_IsTireOrAccRO__c
                FROM WorkOrder
                WHERE Id IN :parentWOIds
                WITH SECURITY_ENFORCED
            ]) {
                workOrdersToClone.add(wo);
            }
            // Clone Closed - Cannot Complete child WOs
            CS_RepairOrderTriggerHandler.processClosedWorkOrders(workOrdersToClone, caseToSAMap);

            // Additionally, create child WOs for remaining CS_Concern child cases under the same parent Case(s)
            // Collect parent CaseIds from the parent WOs we just processed
            Set<Id> parentCaseIdsForRemainingConcerns = new Set<Id>();
            for (WorkOrder pwo : workOrdersToClone) {
                if (pwo.CaseId != null) {
                    parentCaseIdsForRemainingConcerns.add(pwo.CaseId);
                }
            }

            if (!parentCaseIdsForRemainingConcerns.isEmpty()) {
                // Get all concern cases under these parent cases (exclude removed)
                // Use fieldset defined earlier for createWorkOrder prerequisites
                String fieldSetNameForRemaining = CS_Constants.CS_CASEFIELDSETFORRO;
                Set<String> fieldNamesForRemaining = new Set<String>();
                for (Schema.FieldSetMember f : Schema.SObjectType.Case.FieldSets.getMap().get(fieldSetNameForRemaining).getFields()) {
                    fieldNamesForRemaining.add(f.getFieldPath());
                }
                String fieldsToQueryForRemaining = String.join(new List<String>(fieldNamesForRemaining), ',');

                // Note: filter by RecordType to CS_Concern and exclude removed cases

                Schema.SObjectType caseType = Case.sObjectType;
                String baseSelect = 'SELECT ' + fieldsToQueryForRemaining + ' FROM Case';
                String whereClause = ' WHERE ParentId IN :parentCaseIdsForRemainingConcerns AND RecordTypeId = :concernRecordTypeId AND Status != :removedStatus';
                Id concernRecordTypeId = CS_FSGenericUtility.getRecordTypeId(CS_Constants.CS_Case, CS_Constants.CS_CONSERNRTDEV);
                String removedStatus = CS_Constants.CS_REMOVED;
                // Use Database.query with inline bind variables only for static parts; dynamic fields are in the select list
                List<Case> allRemainingConcernCases = Database.query(baseSelect + whereClause, AccessLevel.User_Mode);
                system.debug('allRemainingConcernCases --' + allRemainingConcernCases);
                if (!allRemainingConcernCases.isEmpty()) {
                    // Identify which concern cases already have a child WorkOrder (avoid duplicates)
                    Set<Id> remainingConcernIds = new Set<Id>();
                    for (Case c : allRemainingConcernCases) {
                        remainingConcernIds.add(c.Id);
                    }

                    // Query for existing WorkOrders where CaseId matches our concern cases
                    // Instead of building a map keyed by WorkOrder.Id, build a set of CaseIds that already have WOs
                    Set<Id> concernIdsWithExistingWO = new Set<Id>();
                    for (WorkOrder wo : [
                        SELECT Id, CaseId, status
                        FROM WorkOrder
                        WHERE CaseId IN :remainingConcernIds
                        WITH USER_MODE
                    ]) {
                        system.debug('status of --'+wo.Status);
                        concernIdsWithExistingWO.add(wo.CaseId);
                    }

                    // Filter concerns that do NOT have a WO yet (avoid nested loop)
                    List<Case> concernsNeedingWO = new List<Case>();
                    for (Case concern : allRemainingConcernCases) {
                        if (!concernIdsWithExistingWO.contains(concern.Id)) {
                            concernsNeedingWO.add(concern);
                        }
                    }
                    system.debug('concernsNeedingWO --' + concernsNeedingWO);
                    List<WorkOrder> parentROToUpdate = new List<WorkOrder>();

                    if (!concernsNeedingWO.isEmpty()) {
                        CS_CaseTriggerHandler.createWorkOrder(concernsNeedingWO);

                        for(WorkOrder woCreated : [SELECT Id, CaseId, ParentWorkOrderId FROM WorkOrder WHERE CaseId IN :concernsNeedingWO]){
                            system.debug('woCreated--'+woCreated);
                            if(woCreated.ParentWorkOrderId != null){
                                parentROToUpdate.add(new WorkOrder(Id = woCreated.ParentWorkOrderId,
                                    Status = CS_Constants.CS_NEW));
                            }
                        }
                        Database.Update(parentROToUpdate, AccessLevel.User_Mode);
                    }
                }
            }
        }

        if (!caseIds.isEmpty()) {
            for (Case c : [
                SELECT Id, ParentId FROM Case
                WHERE ParentId IN :caseIds
                WITH SECURITY_ENFORCED
            ]) {
                if (c.ParentId != null) {
                    caseIds.add(c.Id);
                }
            }

            String fieldSetName = CS_Constants.CS_CASEFIELDSETFORRO;
            Set<String> fieldNames = new Set<String>();

            for (Schema.FieldSetMember f : Schema.SObjectType.Case.FieldSets.getMap().get(fieldSetName).getFields()) {
                fieldNames.add(f.getFieldPath());
            }

            // Convert the set of field names into a comma-separated string
            String fieldsToQuery = String.join(new List<String>(fieldNames), ',');

            // Build the dynamic SOQL query
            String soqlQuery = 'SELECT ' + fieldsToQuery + ' FROM Case WHERE (Id IN :caseIds OR ParentId IN :caseIds) AND Status != \'' + CS_Constants.CS_REMOVED + '\'';
            system.debug('>>>fieldsToQuery'+fieldsToQuery);

            caseList = Database.query(soqlQuery, AccessLevel.User_Mode);
            //caseList = Database.query(soqlQuery, AccessLevel.System_Mode);
            Set<Case> caseSet = new Set<Case>(caseList);

            Map<Id, List<Case>> fsInquiryToConcernCasesMap = new Map<Id, List<Case>>();
            Map<Id, Case> fsInquiryToParentCasesMap = new Map<Id, Case>();

            for (Case c : caseList) {
                if (c.RecordTypeId == CS_FSGenericUtility.getRecordTypeId(CS_Constants.CS_Case, CS_Constants.CS_FSINQUIRYRTDEV)
                    || c.RecordTypeId == CS_FSGenericUtility.getRecordTypeId(CS_Constants.CS_Case, CS_Constants.CS_CPORT)) {
                    fsInquiryToConcernCasesMap.put(c.Id, new List<Case>());
                    fsInquiryToParentCasesMap.put(c.Id, c);
                }
            }

            system.debug('fsInquiryToParentCasesMap====>' + fsInquiryToParentCasesMap);

            for (Case c : caseList) {
                if (c.RecordTypeId == CS_FSGenericUtility.getRecordTypeId(CS_Constants.CS_Case, CS_Constants.CS_CONSERNRTDEV)) {
                    if (c.ParentId != null && fsInquiryToConcernCasesMap.containsKey(c.ParentId)) {
                        fsInquiryToConcernCasesMap.get(c.ParentId).add(c);
                    }
                }
            }
            system.debug('fsInquiryToConcernCasesMap====>' + fsInquiryToConcernCasesMap);

            List<Case> concernsToUpdateClose = new List<Case>();
            Set<Id> serviceAppointmentIdsToUpdateCompleted = new Set<Id>();

            concernTypeCategoryAndSubCategories = createConcernTypeMap(CS_Constants.CS_BODYANDCOLLISION);

            for (Id fsInquiryId : fsInquiryToConcernCasesMap.keySet()) {
                List<Case> concernCases = fsInquiryToConcernCasesMap.get(fsInquiryId);
                if (concernCases != null && !concernCases.isEmpty()) {
                    List<Case> skippableConcerns = new List<Case>();
                    List<Case> ROcreatableConcerns = new List<Case>();

                    for (Case concernCase : concernCases) {
                        if (isSkippableBPInsurance(concernCase)) {
                            skippableConcerns.add(concernCase);
                        }
                        else{
                            ROcreatableConcerns.add(concernCase);
                        }
                    }

                    //skippable concerns = close Parent case and SA completed.No RO
                    if (ROcreatableConcerns.isEmpty()) {
                        concernsToUpdateClose.addAll(skippableConcerns);
                        concernsToUpdateClose.add(new Case(Id = fsInquiryId));
                        if (parentRecordIdToServiceAppointments.containsKey(fsInquiryId)) {
                            serviceAppointmentIdsToUpdateCompleted.addAll(parentRecordIdToServiceAppointments.get(fsInquiryId));
                        }

                        caseSet.removeAll(new Set<Case>(concernCases));
                        if (fsInquiryToParentCasesMap.containsKey(fsInquiryId)) {
                            caseSet.remove(fsInquiryToParentCasesMap.get(fsInquiryId));
                        }
                    }
                        else {

                            if (!skippableConcerns.isEmpty()) {
                                concernsToUpdateClose.addAll(skippableConcerns);
                                caseSet.removeAll(new Set<Case>(skippableConcerns));
                            }
                        }
                }
            }
            system.debug('concernsToUpdateClose====>' + concernsToUpdateClose);
            system.debug('serviceAppointmentIdsToUpdateCompleted====>' + serviceAppointmentIdsToUpdateCompleted);
            system.debug('caseSet====>' + caseSet);
            updateCompletedAppointments(new List<Id>(serviceAppointmentIdsToUpdateCompleted));
            //Added by Gagan
            updateCaseRecords(concernsToUpdateClose);
            //Closed - Added by Gagan
            if (!caseSet.isEmpty()) {
                updateCaseRecords(concernsToUpdateClose);
                caseList.clear();
                caseList.addAll(caseSet);
                CS_CaseTriggerHandler.createWorkOrder(caseList);
                updateFSInquiryCasesToDiagnosis(fsInquiryToParentCasesMap);
            }
        }


    }

    public static void handleVehiclePickup(List<ServiceAppointment> serviceAppointmentList){
    // For Vehicle Pickup logic
        List<Id> vehiclePickupWOIds = new List<Id>();
        Map<Id, Id> workOrderToCaseMap = new Map<Id, Id>();
        List<Case> caseList = new List<Case>();
        List<Id> parentWOIds = new List<Id>();

            for (ServiceAppointment sa : serviceAppointmentList) {
                // ✅ Move Vehicle Pickup check here — inside the loop
            if (sa.AppointmentType == 'Vehicle Pickup' && sa.CS_WorkOrder__c != null && sa.CS_Case__c != null) {
                vehiclePickupWOIds.add(sa.CS_WorkOrder__c);
                workOrderToCaseMap.put(sa.CS_WorkOrder__c, sa.CS_Case__c);
            }
            }
            if (!vehiclePickupWOIds.isEmpty()) {
            List<WorkOrder> childWorkOrders = [
                SELECT Id, ParentWorkOrderId, Status
                FROM WorkOrder
                WHERE ParentWorkOrderId IN :vehiclePickupWOIds
                AND Status = :CS_Constants.CS_CLOSEDCANNOTCOMPLETE
                WITH SECURITY_ENFORCED
            ];
            Set<Id> parentWOWithClosedCannotComplete = new Set<Id>();
            if(!childWorkOrders.isEmpty()){
            for (WorkOrder childWO : childWorkOrders) {
                parentWOWithClosedCannotComplete.add(childWO.ParentWorkOrderId);
            }
            }
            List<Case> casesToUpdate = new List<Case>();
            for (Id parentWOId : parentWOWithClosedCannotComplete) {
                if (workOrderToCaseMap.containsKey(parentWOId)) {
                    casesToUpdate.add(new Case(
                        Id = workOrderToCaseMap.get(parentWOId),
                            CS_ROStatusForCustomer__c = CS_Constants.CS_INPROGRESSSTATUS,
                            Status = CS_Constants.CS_INPROGRESSSTATUS
                    ));
                }
            }
            if (!casesToUpdate.isEmpty()) {
                update casesToUpdate;
            }
        }
    }


        /**
    * @description : method to handle updation of ServiceAppointment status to completed of Insurancy Payment Type
    * @author: Meghana
    * @param: serviceAppointmentIds
    * @return void
    **/

        @future
        public static void updateCompletedAppointments(List<Id> serviceAppointmentIds){
            ServiceAppointment[] serviceAppointmentsToUpdateCompleted = new ServiceAppointment[]{};
            if(!serviceAppointmentIds.isEmpty()){
                for (Id serviceAppointmentId : serviceAppointmentIds){
                    serviceAppointmentsToUpdateCompleted.add(new ServiceAppointment(
                        Id = serviceAppointmentId, Status = CS_Constants.CS_COMPLETED, ActualEndTime = System.now()));
                }
                if(ServiceAppointment.sObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isUpdateable()){
                    update serviceAppointmentsToUpdateCompleted;
                }
            }

        }

        /**
    * @description : method to handle updation of Case/Concern status to closed of Insurancy Payment Type
    * @author: Meghana
    * @param: serviceAppointmentIds
    * @return void
    **/

        private static void updateCaseRecords(List<Case> concernsToUpdateClose){
            if(!concernsToUpdateClose.isEmpty()) {
                for(Case concernCase : concernsToUpdateClose) {
                    concernCase.Status = CS_Constants.CS_CLOSED;
                    concernCase.CS_CaseResolutionComments__c = Label.CS_CaseResolutionComments;
                }
                if(Case.sObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isUpdateable()){
                    update concernsToUpdateClose;
                }
            }
        }



        private static Boolean checkIfPaymentTypeInsurancePay(Case c){
            return c.CS_PaymentType__c!=null && c.CS_PaymentType__c == CS_Constants.CS_INSURANCEPAY;
        }

        private static Boolean isSkippableBPInsurance(Case c) {
            return checkIfPaymentTypeInsurancePay(c) && checkIfConcernTypeBodyCollision(c, concernTypeCategoryAndSubCategories);
        }

        private static Map<String, String[]> createConcernTypeMap(String concernType){
            Map<String, String[]> concernTypeCategoryAndSubCategories = new Map<String, String[]>();
            for(CS_ConcernTypeMapping__mdt concernTypeMap : [SELECT Id, CS_Category__c, CS_SubCategory__c
            FROM CS_ConcernTypeMapping__mdt WHERE CS_ConcernType__c =:concernType WITH SECURITY_ENFORCED]){
                String[] subCategories = concernTypeCategoryAndSubCategories.get(concernTypeMap.CS_Category__c);
                if(subCategories == null){
                    subCategories = new String[]{};
                concernTypeCategoryAndSubCategories.put(concernTypeMap.CS_Category__c, subCategories);
            }
            subCategories.add(concernTypeMap.CS_SubCategory__c);
            }

            return concernTypeCategoryAndSubCategories;
        }

        /**
    * @description : Updates FS Inquiry cases' CS_ROStatusForCustomer__c field to 'Diagnosis'
    * @param fsInquiryToParentCasesMap : Map of FS Inquiry case Ids to Case records
    **/
    private static void updateFSInquiryCasesToDiagnosis(Map<Id, Case> fsInquiryToParentCasesMap) {
        if (fsInquiryToParentCasesMap == null || fsInquiryToParentCasesMap.isEmpty()) {
            return;
        }

        List<Case> casesToUpdate = new List<Case>();

        for (Case inquiryCase : fsInquiryToParentCasesMap.values()) {
            if (inquiryCase != null && Case.sObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isUpdateable()) {
                inquiryCase.CS_ROStatusForCustomer__c = 'Diagnosis';
                inquiryCase.Status = 'In Progress';
                casesToUpdate.add(inquiryCase);
            }
        }

        if (!casesToUpdate.isEmpty()) {
            update casesToUpdate;
        }
    }

        private static Boolean checkIfConcernTypeBodyCollision(Case c, Map<String, String[]> concernTypeCategoryAndSubCategories){
            return c.CS_ConcernType__c == CS_Constants.CS_BODYANDCOLLISION &&
                concernTypeCategoryAndSubCategories.containsKey(c.CS_Category__c) &&
                concernTypeCategoryAndSubCategories.get(c.CS_Category__c).contains(c.CS_SubCategory__c);
        }
}public with sharing class CS_ServiceAppointmentTriggerHandler {
    public CS_ServiceAppointmentTriggerHandler() {

    }
}