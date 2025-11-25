@IsTest
private class OrgA_ContactSyncRestTest {

    // Utility method to create Rest Context
    private static void setupRestContext(String body) {
        RestRequest req = new RestRequest();
        req.httpMethod = 'POST';
        req.requestUri = '/services/apexrest/OrgAContacts';
        req.addHeader('Content-Type', 'application/json');
        req.requestBody = (body == null) ? null : Blob.valueOf(body);

        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    // ---------------------------------------------
    // 1) Test: Valid contact + account found → SUCCESS
    // ---------------------------------------------
    @IsTest
    static void testValidUpsert() {

        // Create an Account (Org A will map by AccountName)
        Account acc = new Account(Name = 'StartApps');
        insert acc;

        // Contact exists → update
        Contact c = new Contact(
            FirstName = 'Old',
            LastName = 'Name',
            Email = 'update@test.com',
            AccountId = acc.Id
        );
        insert c;

        // JSON Body with 2 contacts → one updating, one new
        String jsonBody = '[{"firstName":"Akshay","lastName":"Verma","email":"update@test.com","phone":"999","accountName":"StartApps"},' +
                          '{"firstName":"New","lastName":"Contact","email":"new@test.com","phone":"888","accountName":"StartApps"}]';

        setupRestContext(jsonBody);

        Test.startTest();
        OrgA_ContactSyncRest.upsertContacts();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        // Check database results
        Contact updated = [SELECT FirstName, Phone FROM Contact WHERE Email='update@test.com' LIMIT 1];
        System.assertEquals('Akshay', updated.FirstName);
        System.assertEquals('999', updated.Phone);

        Contact created = [SELECT FirstName, Account.Name FROM Contact WHERE Email='new@test.com' LIMIT 1];
        System.assertEquals('New', created.FirstName);
        System.assertEquals('StartApps', created.Account.Name);
    }


    // ---------------------------------------------
    // 2) Test: Empty request body
    // ---------------------------------------------
    @IsTest
    static void testEmptyBody() {

        setupRestContext(null);

        Test.startTest();
        OrgA_ContactSyncRest.upsertContacts();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    // ---------------------------------------------
    // 3) Test: Invalid JSON
    // ---------------------------------------------
    @IsTest
    static void testInvalidJson() {

        setupRestContext('{"firstName":'); // broken JSON

        Test.startTest();
        OrgA_ContactSyncRest.upsertContacts();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    // ---------------------------------------------
    // 4) Test: JSON array but empty
    // ---------------------------------------------
    @IsTest
    static void testEmptyArray() {

        setupRestContext('[]');

        Test.startTest();
        OrgA_ContactSyncRest.upsertContacts();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    // ---------------------------------------------
    // 5) Test: No emails → error
    // ---------------------------------------------
    @IsTest
    static void testNoEmails() {

        setupRestContext('[{"firstName":"A","lastName":"B"}]'); // no email field

        Test.startTest();
        OrgA_ContactSyncRest.upsertContacts();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    // ---------------------------------------------
    // 6) Test: DML exception branch (force error)
    // ---------------------------------------------
    @IsTest
    static void testDmlException() {

        // Create JSON where contact will fail (missing LastName)
        String jsonBody = '[{"firstName":"OnlyFirst","email":"fail@test.com","accountName":"XYZ"}]';

        setupRestContext(jsonBody);

        Test.startTest();
        OrgA_ContactSyncRest.upsertContacts();
        Test.stopTest();

        // Contact missing LastName → DML error handled
        System.assertEquals(200, RestContext.response.statusCode);
        System.assert(RestContext.response.responseBody.toString().contains('fail@test.com'));
        System.assert(RestContext.response.responseBody.toString().contains('REQUIRED_FIELD_MISSING'));
    }

    // ---------------------------------------------
    // 7) Test: Account name provided but not found (should still create Contact)
    // ---------------------------------------------
    @IsTest
    static void testAccountNotFound() {

        setupRestContext('[{"firstName":"Ak","lastName":"Ver","email":"noacc@test.com","accountName":"Unknown"}]');

        Test.startTest();
        OrgA_ContactSyncRest.upsertContacts();
        Test.stopTest();

        Contact c = [SELECT Id, AccountId FROM Contact WHERE Email='noacc@test.com' LIMIT 1];
        System.assertEquals(null, c.AccountId, 'Should not assign Account if not found');
    }
}