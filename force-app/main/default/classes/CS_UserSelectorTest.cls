/**
 * @description       : Unit tests for CS_UserSelector selector
 * Verifies:
 *  - getSObjectFieldList returns expected default fields
 *  - getSObjectType returns User.sObjectType
 *  - selectFieldsFromUser builds SOQL with dynamic fields and conditions
 *  - selectFieldsFromUserRecord builds SOQL with dynamic fields, conditions and limit
 *  - Bulk behavior (no SOQL/DML in loops in tests; selector used once per test)
 * Notes:
 *  - No SeeAllData. Creates its own Users with runAs to satisfy profile/perm constraints.
 *  - Uses Database.query to validate dynamic SOQL execution and result mapping.
 */
@IsTest
private class CS_UserSelectorTest {
    // Minimal field set needed for creating test users
    private static final Set<Schema.SObjectField> BASE_FIELDS = new Set<Schema.SObjectField>{
        User.Id, User.Name
    };

    @TestSetup
    static void setup() {
        // Create a role (optional for uniqueness or hierarchy queries)
        UserRole ur = new UserRole(Name = 'Test Role');
        insert ur;

        // Create two distinct profiles by querying existing standard profiles
        // We cannot insert Profiles; pick any two existing to vary data. If only one, use same for both.
        Profile p = [SELECT Id FROM Profile WHERE Name != null LIMIT 1];
        // Create users with unique usernames/emails. Use GMT time to ensure unique usernames.
        Datetime now = System.now();
        String uniq1 = String.valueOf(now.getTime());
        String uniq2 = String.valueOf(now.getTime() + 1);

        User u1 = new User(
            FirstName = 'Alpha',
            LastName = 'User',
            Email = 'alpha' + uniq1 + '@example.com',
            Username = 'alpha' + uniq1 + '@example.com',
            Alias = 'auser',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        User u2 = new User(
            FirstName = 'Beta',
            LastName = 'User',
            Email = 'beta' + uniq2 + '@example.com',
            Username = 'beta' + uniq2 + '@example.com',
            Alias = 'buser',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id,
            UserRoleId = ur.Id
        );
        insert new List<User>{ u1, u2 };
    }

    @IsTest
    static void test_getSObjectType_and_FieldList() {
        System.runAs(getAnyNonAdminUser()) {
            CS_UserSelector sel = new CS_UserSelector();

            // Validate SObjectType
            System.assertEquals(User.SObjectType, sel.getSObjectType(), 'Selector should return User.sObjectType');

            // Validate default field list
            List<Schema.SObjectField> fields = sel.getSObjectFieldList();
            System.assertNotEquals(null, fields, 'Field list should not be null');
            System.assert(fields.size() > 0, 'Field list should have at least one field');
            System.assert(fields.contains(User.Id), 'Default fields should include User.Id');
        }
    }

    @IsTest
    static void test_selectFieldsFromUser_withConditions() {
        System.runAs(getAnyNonAdminUser()) {
            CS_UserSelector sel = new CS_UserSelector();

            // Build dynamic fields
            Set<String> fieldNames = new Set<String>{
                'Id',
                'Name',
                'Email'
            };
            // Condition: pick users whose FirstName IN ('Alpha','Beta')
            String conditions = 'FirstName IN (\'Alpha\', \'Beta\')';

            Test.startTest();
            List<User> results = sel.selectFieldsFromUser(fieldNames, conditions);
            Test.stopTest();

            System.assertNotEquals(null, results, 'Results should not be null');
            System.assertEquals(2, results.size(), 'Should find both Alpha and Beta users');

            // Validate that selected fields are populated (Id always, Name should be populated)
            for (User u : results) {
                System.assertNotEquals(null, u.Id, 'Id should be populated');
                System.assertNotEquals(null, u.Name, 'Name should be populated');
                // Email was requested; not necessarily required for assertion but check not null
                System.assertNotEquals(null, u.Email, 'Email should be populated for requested field');
            }
        }
    }

    @IsTest
    static void test_selectFieldsFromUserRecord_withLimit() {
        System.runAs(getAnyNonAdminUser()) {
            CS_UserSelector sel = new CS_UserSelector();

            Set<String> fieldNames = new Set<String>{ 'Id', 'FirstName', 'LastName' };
            String conditions = 'FirstName IN (\'Alpha\', \'Beta\')';
            Integer limitVal = 1;

            Test.startTest();
            List<User> results = sel.selectFieldsFromUserRecord(fieldNames, conditions, limitVal);
            Test.stopTest();

            System.assertNotEquals(null, results, 'Results should not be null');
            System.assertEquals(1, results.size(), 'Limit should constrain result size to 1');

            User u = results[0];
            System.assertNotEquals(null, u.Id, 'Id should be populated');
            System.assertNotEquals(null, u.FirstName, 'FirstName should be populated');
            System.assertNotEquals(null, u.LastName, 'LastName should be populated');
        }
    }

    @IsTest
    static void test_bulk_style_usage_no_errors() {
        System.runAs(getAnyNonAdminUser()) {
            CS_UserSelector sel = new CS_UserSelector();

            // Simulate repeated calls in a single transaction to ensure selector is safe in bulk context
            Set<String> fields = new Set<String>{ 'Id' };
            String cond = 'FirstName != null';

            Test.startTest();
            List<User> batch1 = sel.selectFieldsFromUser(fields, cond);
            List<User> batch2 = sel.selectFieldsFromUserRecord(fields, cond, 200);
            Test.stopTest();

            System.assert(batch1.size() >= 2, 'Should return at least the two setup users');
            System.assert(batch2.size() >= 1, 'Should return at least one user with limit');
        }
    }

    // Utility: obtain any non-admin user created in @TestSetup to run queries under realistic sharing
    private static User getAnyNonAdminUser() {
        // Pick the user with FirstName Alpha if available
        List<User> us = [SELECT Id FROM User WHERE FirstName IN ('Alpha','Beta') ORDER BY FirstName LIMIT 1];
        return us.isEmpty() ? [SELECT Id FROM User LIMIT 1] : us[0];
    }
}
