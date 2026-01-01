@isTest
public class CS_ServiceAppointmentTriggerHandlerTest {
    @TestSetup
    static void makeData(){

        Account accRec;
        Account parentAcc = new Account();
        Contact con;
        Contact con1;
        Vehicle vehicleRec;
        CodeSet cds;
        UserRole role = [SELECT Id, Name, ParentRoleId, DeveloperName FROM UserRole where name = 'SHM CS' limit 1];

        System.runAs(CS_TestDataFactory.constructUserWithRole(CS_Constants.CS_PROFILE_SYS_ADMIN, role.id)){

            accRec = CS_TestDataFactory.constructAccountWithParam('David','Lee',CS_Constants.CS_AccountCustRecTypeDev);
            accRec.CS_SimpleID__c = 'David1234';
            Insert accRec;

            Account accRec1 = CS_TestDataFactory.constructAccount(CS_Constants.CS_AccountCustRecTypeDev);
            Insert accRec1;

            Asset assetRec = CS_TestDataFactory.constructAsset();
            assetRec.AccountId = accRec.Id;
            Insert assetRec;

            Product2 productRec = CS_TestDataFactory.constructProductRec();
            Insert productRec;

            VehicleDefinition vehicleDefRec = CS_TestDataFactory.constructvehicleDefRec();
            vehicleDefRec.ProductId  = productRec.Id;
            Insert vehicleDefRec;

            vehicleRec = CS_TestDataFactory.constructVehicleRec();
            vehicleRec.name = '1HGCM82633A123456';
            vehicleRec.AssetId = assetRec.Id;
            vehicleRec.VehicleDefinitionId = vehicleDefRec.Id;
            vehicleRec.CurrentOwnerId = accRec.Id;
            Insert vehicleRec;

            Account masterAcc = new Account();
            Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(CS_Constants.CS_RepairPartnerRecordType).getRecordTypeId();
            masterAcc.Name = 'Crash Champion';
            masterAcc.RecordTypeId = recordTypeId;
            Insert masterAcc;

            Id parentAccRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(CS_Constants.CS_RepairPartnerFacilityRecordType).getRecordTypeId();
            parentAcc.Name = 'Crash Champion #2034 - Los Angeles Watts Avenue';
            parentAcc.ParentId = masterAcc.id;
            parentAcc.RecordTypeId = parentAccRecTypeId;
            Insert parentAcc;

            con = CS_TestDataFactory.constructContactRecWithParam('Crash Champion','Manager');
            con.AccountId = masterAcc.id;
            insert con;

            con1 = CS_TestDataFactory.constructContactRecWithParam('Crash Champion','Store Representative');
            con1.AccountId = masterAcc.id;
            insert con1;

            AccountContactRelation acr = new AccountContactRelation();
            acr.accountid = parentAcc.Id;
            acr.contactid = con1.Id;
            acr.Roles = 'Store Representative';
            acr.IsActive = true;
            Insert acr;

            AccountContactRelation acr1 = new AccountContactRelation();
            acr1.accountid = parentAcc.Id;
            acr1.contactid = con.Id;
            acr1.Roles = 'Manager';
            acr1.IsActive = true;
            Insert acr1;
        }


        Profile userProfileId = [SELECT Id, name FROM Profile WHERE Name = 'CS Repair Partner User' LIMIT 1];
        String uniqueUserName = 'api' + DateTime.now().getTime() + '@testorg.com';
        User testUser = new User(LastName = 'Manager',
                                    FirstName = 'Crash Champion',
                                    Alias = 'ccM',
                                    Email = 'ccm@shm.com',
                                    ProfileId = userProfileId.Id,
                                    Username = uniqueUserName+2,
                                    TimeZoneSidKey = 'America/Los_Angeles',
                                    LanguageLocaleKey = 'en_US',
                                    EmailEncodingKey = 'UTF-8',
                                    LocaleSidKey = 'en_US'
                                );
        testUser.contactId = con.Id;
        Insert testUser;

        Profile fsUserProfileId = [SELECT Id, name FROM Profile WHERE Name = 'CS Field Service' LIMIT 1];
        String uniqueUserName1 = 'api' + DateTime.now().getTime() + '@testorg.com';
        User testISAUser = new User(LastName = 'Test',
                                    FirstName = 'ISA',
                                    Alias = 'isa',
                                    Email = 'isa@shm.com',
                                    ProfileId = fsUserProfileId.Id,
                                    Username = uniqueUserName1+2,
                                    TimeZoneSidKey = 'America/Los_Angeles',
                                    LanguageLocaleKey = 'en_US',
                                    EmailEncodingKey = 'UTF-8',
                                    LocaleSidKey = 'en_US'
                                    );
        Insert testISAUser;

        Profile sysAdminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User adminUser = new User(LastName = 'Admin',
                                 FirstName = 'System',
                                 Alias = 'sysAd',
                                 Email = 'sysadmin@shm.com',
                                 ProfileId = sysAdminProfile.Id,
                                 Username = uniqueUserName + 'admin',
                                 TimeZoneSidKey = 'America/Los_Angeles',
                                 LanguageLocaleKey = 'en_US',
                                 EmailEncodingKey = 'UTF-8',
                                 LocaleSidKey = 'en_US'
                                );
        Insert adminUser;

        PermissionSet permissionSet = [SELECT Id FROM PermissionSet WHERE Name = 'CS_RepairPartnerAgent' LIMIT 1];
        PermissionSet permissionSetISA = [SELECT Id FROM PermissionSet WHERE Name = 'CS_InternalServiceAdvisor' LIMIT 1];
        PermissionSet permissionSetAdmin = [SELECT Id FROM PermissionSet WHERE Name = 'CS_SystemAdministrator' LIMIT 1];

        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = testUser.Id,
            PermissionSetId = permissionSet.Id
        );
        insert psa;

        PermissionSetAssignment psaISA = new PermissionSetAssignment(
            AssigneeId = testISAUser.Id,
            PermissionSetId = permissionSetISA.Id
        );
        insert psaISA;

        PermissionSet permissionSet1 = [SELECT Id FROM PermissionSet WHERE Name = 'CS_AutomotiveCloudForExperienceUser' LIMIT 1];
        PermissionSetAssignment psa1 = new PermissionSetAssignment(
            AssigneeId = testUser.Id,
            PermissionSetId = permissionSet1.Id
        );
        insert psa1;

        PermissionSetAssignment psaAdmin = new PermissionSetAssignment(
            AssigneeId = adminUser.Id,
            PermissionSetId = permissionSetAdmin.Id
        );
        insert psaAdmin;

        system.runAs(adminUser){
            AccountShare acs = new AccountShare(
                AccountId = accRec.id,
                UserOrGroupId = testUser.id,
                AccountAccessLevel = 'Read',
                OpportunityAccessLevel = 'None',
                CaseAccessLevel = 'None'
            );
            insert acs;
        }

        system.runAs(adminUser){

            // Setup Parent Case
            Id caseRecordTypeId =Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get(CS_Constants.CS_FSINQUIRYRTDEV).getRecordTypeId();
            case constructCaseRec = new Case();
            constructCaseRec.AccountId = accRec.Id;
            constructCaseRec.RecordTypeId = caseRecordTypeId;
            constructCaseRec.CS_Vehicle__c = vehicleRec.id;
            constructCaseRec.CS_RepairPartnerFacility__c = parentAcc.id;
            constructCaseRec.CS_RepairPartnerServiceAdvisor__c = con1.id;
            Insert constructCaseRec;

            // Setup Concerns
            Case concHVAC = new Case();
            concHVAC.CS_Category__c = 'Maintenance';
            concHVAC.CS_SubCategory__c = 'HVAC Cleaning';
            concHVAC.CS_ConcernType__c = 'Maintenance';
            concHVAC.CS_RepairPartnerFacility__c = parentAcc.id;
            concHVAC.CS_RepairPartnerServiceAdvisor__c = con1.id;
            concHVAC.Description = 'HVAC Cleaning';
            concHVAC.ParentId = constructCaseRec.id;
            concHVAC.RecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get(CS_Constants.CS_CONSERNRTDEV).getRecordTypeId();
            insert concHVAC;

            FSL.GlobalAPIS.addStatusTransition(CS_Constants.CS_SCHEDULESTATUS, CS_Constants.CS_INPROGRESSSTATUS);
            FSL.GlobalAPIS.addStatusTransition(CS_Constants.CS_INPROGRESSSTATUS, CS_Constants.CS_CHECKEDINSTATUS);
            FSL.GlobalAPIS.addStatusTransition(CS_Constants.CS_CHECKEDINSTATUS, CS_Constants.CS_COMPLETED);

            // Fetch specific Service Appointment Record Type for Field Service
            Id saRecordTypeId = Schema.SObjectType.ServiceAppointment.getRecordTypeInfosByDeveloperName().get(CS_Constants.CS_SAFIELDSERVICERTDEV).getRecordTypeId();

            ServiceAppointment sa = CS_TestDataFactory.constructSARecords();
            sa.CS_Case__c = constructCaseRec.Id;
            sa.ParentRecordId = constructCaseRec.Id;
            sa.RecordTypeId = saRecordTypeId;
            sa.SchedStartTime = System.now().addHours(2);
            sa.SchedEndTime = System.now().addHours(4);
            sa.Status = CS_Constants.CS_INPROGRESSSTATUS;
            sa.CS_RepairPartnerFacility__c = parentAcc.Id;
            sa.CS_RepairPartnerServiceAdvisor__c = con1.id;
            sa.CS_Mileage__c = '15';
            Insert sa;
            sa.Status = CS_Constants.CS_CHECKEDINSTATUS;
            update sa;

            CS_WorkOrderController.ServiceAppointmentWrapper saWrap = CS_TestDataFactory.constructServiceAppointmentWrapper();
            saWrap.Id = sa.Id;
            saWrap.objectName = 'ServiceAppointment';
            CS_WorkOrderController.updateCheckInDetailsInSA(saWrap, new List<Case>{ concHVAC }, 'Submit');
            CS_WorkOrderController.updateCheckInDetailsInSA(saWrap, new List<Case>{ concHVAC }, 'Next');

            WorkOrder wo = [SELECT Id FROM WorkOrder WHERE RecordType.DeveloperName = :CS_Constants.CS_PARENTWORTDEV LIMIT 1];

        }
    }
    @isTest
    public static void handleWorkOrderCreationTest() {
        User runUser = [SELECT Id FROM User WHERE Email = 'sysadmin@shm.com' LIMIT 1];
        WorkOrder wo = [select id from WorkOrder where RecordType.DeveloperName = :CS_COnstants.CS_PARENTWORTDEV limit 1];
        wo.CS_IsTireOrAccRO__c = true;
        update wo;
        System.runAs(runUser) {
            ServiceAppointment sAppointment = [Select Id,Status,CS_WorkOrder__c,AppointmentType,CS_WorkOrder__r.CS_IsTireOrAccRO__c from ServiceAppointment limit 1];
            sAppointment.CS_WorkOrder__c = wo.Id;
            sAppointment.AppointmentType = 'Revisit';
            test.startTest();
            update sAppointment;

            test.stopTest();
        }
    }

    @isTest
    public static void handleWorkOrderCreationTest1() {
        User runUser = [SELECT Id FROM User WHERE Email = 'ccm@shm.com' LIMIT 1];
        WorkOrder wo = [select id,CS_IsTireOrAccRO__c from WorkOrder where RecordType.DeveloperName = :CS_COnstants.CS_PARENTWORTDEV limit 1];
        System.runAs(runUser) {
            ServiceAppointment sAppointment = [Select Id,Status,CS_WorkOrder__c,AppointmentType from ServiceAppointment limit 1];
            sAppointment.CS_WorkOrder__c = wo.Id;
            sAppointment.AppointmentType = CS_Constants.CS_VEHICLEPICKUP;
            test.startTest();
            update sAppointment;
            test.stopTest();
        }
    }

     /* ======================================================================
       TEST 3 – Future method coverage
       ====================================================================== */
    @isTest
    static void updateCompletedAppointmentsTest() {

        ServiceAppointment sa = [SELECT Id FROM ServiceAppointment LIMIT 1];

        Test.startTest();
            CS_ServiceAppointmentTriggerHandler.updateCompletedAppointments(
                new List<Id>{ sa.Id }
            );
        Test.stopTest();

        sa = [SELECT Status FROM ServiceAppointment WHERE Id=:sa.Id];
        System.assertEquals(CS_Constants.CS_COMPLETED, sa.Status);
    }
}