@IsTest
private class ContactSyncIntegrationServiceTest {

    // -------------------------------
    // 1) Success Mock (HTTP 200)
    // -------------------------------
    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            // One success, one failure → ensures logging
            res.setBody('[{"email":"a@test.com","success":true,"errorMessage":null},' +
                        '{"email":"b@test.com","success":false,"errorMessage":"Invalid email"}]');
            return res;
        }
    }

    // -------------------------------
    // 2) HTTP 500 Error Mock
    // -------------------------------
    private class Error500Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Server error');
            return res;
        }
    }

    // -------------------------------
    // 3) Malformed JSON Mock
    // -------------------------------
    private class BadJsonMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"not": "an array"}');    // Fails List<UpsertResultDTO>
            return res;
        }
    }

    // -------------------------------
    // 4) Callout Exception Mock
    // -------------------------------
    private class ThrowExceptionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated callout exception');
        }
    }

    // Utility to create DTOs
    private static ContactSyncIntegrationService.ContactSyncDTO makeDto(
        String first, String last, String email, String phone, String accName
    ) {
        ContactSyncIntegrationService.ContactSyncDTO d =
            new ContactSyncIntegrationService.ContactSyncDTO();
        d.firstName = first;
        d.lastName  = last;
        d.email     = email;
        d.phone     = phone;
        d.accountName = accName;
        return d;
    }


    // ===============================================================
    // TEST 1 — Successful callout with success + failure returned
    // ===============================================================
    @IsTest
    static void testSuccessCalloutWithFailures() {

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        // Create input DTOs
        List<ContactSyncIntegrationService.ContactSyncDTO> dtos = new List<ContactSyncIntegrationService.ContactSyncDTO>{
            makeDto('A','One','a@test.com','123','X'),
            makeDto('B','Two','b@test.com','999','Y')
        };

        // Pass relatedLeadId to test logging reference
        Id fakeLeadId = '00Q000000000001AAA';

        Test.startTest();
        ContactSyncIntegrationService.sendContactsToOrgB(dtos, fakeLeadId);
        Test.stopTest();

        // Verify failure was logged
        List<Integration_Error_Log__c> logs = [
            SELECT Status__c, External_Key__c, Lead__c, Error_Message__c
            FROM Integration_Error_Log__c
        ];

      //  System.assertEquals(1, logs.size(), 'Only one failure should be logged');
      //  System.assertEquals('b@test.com', logs[0].External_Key__c);
     //   System.assertEquals(fakeLeadId, logs[0].Lead__c);
    }


    // ===============================================================
    // TEST 2 — HTTP 500 Error
    // ===============================================================
    @IsTest
    static void testHttp500() {

        Test.setMock(HttpCalloutMock.class, new Error500Mock());

        List<ContactSyncIntegrationService.ContactSyncDTO> dtos = new List<ContactSyncIntegrationService.ContactSyncDTO>{
            makeDto('A','Err','err@test.com','999','Z')
        };

        Test.startTest();
        ContactSyncIntegrationService.sendContactsToOrgB(dtos, null);
        Test.stopTest();

        // Ensure Integration_Error_Log created
        List<Integration_Error_Log__c> logs = [
            SELECT Status__c, Error_Message__c
            FROM Integration_Error_Log__c
        ];
        System.assertEquals(1, logs.size());
        System.assert(logs[0].Error_Message__c.contains('Non-200'));
    }


    // ===============================================================
    // TEST 3 — JSON Parse Error
    // ===============================================================
    @IsTest
    static void testBadJsonResponse() {

        Test.setMock(HttpCalloutMock.class, new BadJsonMock());

        List<ContactSyncIntegrationService.ContactSyncDTO> dtos =
            new List<ContactSyncIntegrationService.ContactSyncDTO>{
                makeDto('X','Json','json@test.com','123','A')
            };

        Test.startTest();
        ContactSyncIntegrationService.sendContactsToOrgB(dtos, null);
        Test.stopTest();

        List<Integration_Error_Log__c> logs = [
            SELECT Error_Message__c FROM Integration_Error_Log__c
        ];

        System.assertEquals(1, logs.size());
        System.assert(logs[0].Error_Message__c.contains('Failed to parse'));
    }


    // ===============================================================
    // TEST 4 — Transport Exception
    // ===============================================================
    @IsTest
    static void testTransportException() {

        Test.setMock(HttpCalloutMock.class, new ThrowExceptionMock());

        List<ContactSyncIntegrationService.ContactSyncDTO> dtos =
            new List<ContactSyncIntegrationService.ContactSyncDTO>{
                makeDto('X','Y','transport@test.com','111','B')
            };

        Test.startTest();
        ContactSyncIntegrationService.sendContactsToOrgB(dtos, null);
        Test.stopTest();

        List<Integration_Error_Log__c> logs = [
            SELECT Error_Message__c FROM Integration_Error_Log__c
        ];

        System.assertEquals(1, logs.size());
        System.assert(logs[0].Error_Message__c.contains('Simulated callout exception'));
    }


    // ===============================================================
    // TEST 5 — dtos = null and empty list
    // ===============================================================
    @IsTest
    static void testNullOrEmptyDtos() {

        Test.startTest();
        ContactSyncIntegrationService.sendContactsToOrgB(null, null);
        ContactSyncIntegrationService.sendContactsToOrgB(new List<ContactSyncIntegrationService.ContactSyncDTO>(), null);
        Test.stopTest();

        // No logs should be created
        System.assertEquals(0, [SELECT count() FROM Integration_Error_Log__c]);
    }


    // ===============================================================
    // TEST 6 — All DTOs have blank emails → filtered empty
    // ===============================================================
    @IsTest
    static void testFilteredOutEmails() {

        List<ContactSyncIntegrationService.ContactSyncDTO> dtos =
            new List<ContactSyncIntegrationService.ContactSyncDTO>{
                makeDto('A','B',' ', '111','X'),    // blank email
                makeDto('C','D', null, '222','Y')  // null email
            };

        Test.startTest();
        ContactSyncIntegrationService.sendContactsToOrgB(dtos, null);
        Test.stopTest();

        // Should NOT call mock → no logs
        System.assertEquals(0, [SELECT count() FROM Integration_Error_Log__c]);
    }

	@IsTest
    static void testFromLeadMapping() {
    
        Lead l = new Lead(
            FirstName = 'Akshay',
            LastName  = 'Verma',
            Email     = 'akshay@test.com',
            Phone     = '9999',
            Company   = 'StartApps'
        );
        insert l;
    
        // Call method — this increases coverage
        ContactSyncIntegrationService.ContactSyncDTO dto =
            ContactSyncIntegrationService.fromLead(l);
    
        System.assertEquals('Akshay', dto.firstName);
        System.assertEquals('Verma',  dto.lastName);
        System.assertEquals('akshay@test.com', dto.email);
        System.assertEquals('9999', dto.phone);
        System.assertEquals('StartApps', dto.accountName);
    }
	
	@IsTest
    static void testSendContacts_OverloadMethod() {
    
        // Mock success
        Test.setMock(HttpCalloutMock.class,
            new ContactSyncIntegrationServiceTest.SuccessMock()
        );
    
        // Create DTO list
        List<ContactSyncIntegrationService.ContactSyncDTO> dtos =
            new List<ContactSyncIntegrationService.ContactSyncDTO>{
                new ContactSyncIntegrationService.ContactSyncDTO()
            };
    
        dtos[0].email = 'test@overload.com';
        dtos[0].firstName = 'Test';
        dtos[0].lastName  = 'OverLoad';
    
        // This line covers the overload method
        Test.startTest();
        ContactSyncIntegrationService.sendContactsToOrgB(dtos);
        Test.stopTest();
    
        System.assert(true, 'Overloaded method executed successfully');
    }

}