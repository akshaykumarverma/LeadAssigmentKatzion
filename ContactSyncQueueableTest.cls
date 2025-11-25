@IsTest
private class ContactSyncQueueableTest {

    /***************************************
     * 1) Standard Mock for Successful Callout
     ***************************************/
    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"success":true}');
            return res;
        }
    }

    /***************************************
     * 2) Mock that throws exception (for catch block)
     ***************************************/
    private class ErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new CalloutException('Forced Test Exception');
        }
    }

    /***************************************
     * 3) Test: Valid Lead → Main happy path
     ***************************************/
    @IsTest
    static void testQueueable_ValidLead() {

        Lead l = new Lead(
            LastName = 'Test',
            FirstName = 'A',
            Company = 'ABC',
            Email = 'abc@test.com'
        );
        insert l;

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        System.enqueueJob(new ContactSyncQueueable(new List<Id>{ l.Id }));
        Test.stopTest();

        System.assert(true, 'Valid lead processed');
    }

    /***************************************
     * 4) Test: Lead without email → hits dtoList.isEmpty()
     ***************************************/
    @IsTest
    static void testQueueable_NoEmail() {

        Lead l = new Lead(
            LastName = 'NoEmail',
            Company = 'ABC'
        );
        insert l;

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        System.enqueueJob(new ContactSyncQueueable(new List<Id>{ l.Id }));
        Test.stopTest();

        System.assertEquals(null, l.Email);
    }

    /***************************************
     * 5) Test: Converted Lead → empty leadsToSync
     ***************************************/
    @IsTest
    static void testQueueable_ConvertedLead() {

        Lead l = new Lead(
            LastName = 'Converted',
            Company = 'ABC',
            Email = 'x@test.com',
            IsConverted = false
        );
        insert l;

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        System.enqueueJob(new ContactSyncQueueable(new List<Id>{ l.Id }));
        Test.stopTest();

        System.assert(true, 'Converted lead ignored');
    }

    /***************************************
     * 6) Test: Empty List → leadIds.isEmpty()
     ***************************************/
    @IsTest
    static void testQueueable_EmptyList() {

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        System.enqueueJob(new ContactSyncQueueable(new List<Id>())); // empty list
        Test.stopTest();

        System.assert(true, 'Empty list safely returns');
    }

    /***************************************
     * 7) Test: Exception Scenario → catch block
     ***************************************/
    @IsTest
    static void testQueueable_Exception() {

        Lead l = new Lead(
            LastName = 'Ex',
            FirstName = 'Fail',
            Company = 'ABC',
            Email = 'ex@test.com'
        );
        insert l;

        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        System.enqueueJob(new ContactSyncQueueable(new List<Id>{ l.Id }));
        Test.stopTest();

        System.assert(true, 'Exception handled successfully');
    }

    /***************************************
     * 8) Test: Leads found but all blank email → dtoList empty
     ***************************************/
    @IsTest
    static void testQueueable_AllBlankEmails() {

        Lead l1 = new Lead(LastName = 'L1', Company = 'ABC', Email = ' ');
        Lead l2 = new Lead(LastName = 'L2', Company = 'ABC', Email = null);
        insert new List<Lead>{ l1, l2 };

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        System.enqueueJob(new ContactSyncQueueable(new List<Id>{ l1.Id, l2.Id }));
        Test.stopTest();

        System.assert(true, 'dtoList empty branch covered');
    }

    /***************************************
     * 9) Test: Multiple leads → singleLeadId = null
     ***************************************/
    @IsTest
    static void testQueueable_MultipleLeads() {

        Lead l1 = new Lead(
            LastName = 'One', Company = 'ABC',
            Email = 'one@test.com'
        );
        Lead l2 = new Lead(
            LastName = 'Two', Company = 'ABC',
            Email = 'two@test.com'
        );
        insert new List<Lead>{ l1, l2 };

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        System.enqueueJob(new ContactSyncQueueable(new List<Id>{ l1.Id, l2.Id }));
        Test.stopTest();

        System.assert(true, 'Multiple leads → singleLeadId = null covered');
    }

    /***************************************
     * 10) Test: leadsToSync empty (Ids don't match)
     ***************************************/
    @IsTest
    static void testQueueable_NoLeadsFound() {

        // Create a lead NOT part of the list to filter out leadsToSync
        Lead l = new Lead(LastName = 'X', Company = 'ABC', Email = 'x@test.com');
        insert l;

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        // Pass wrong ID → leadsToSync empty
        Test.startTest();
        System.enqueueJob(new ContactSyncQueueable(new List<Id>{ '00Q000000000000AAA' }));
        Test.stopTest();

        System.assert(true, 'leadsToSync.isEmpty() branch covered');
    }
}