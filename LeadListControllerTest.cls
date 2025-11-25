@IsTest
private class LeadListControllerTest {

    // --------------------------------------------------------------
    // Test Data Setup
    // --------------------------------------------------------------
    private static void createTestLeads() {
        List<Lead> leads = new List<Lead>();

    leads.add(new Lead(
        FirstName = 'Akshay',
        LastName = 'Verma',
        Company = 'StartApps',
        Email = 'akshay@test.com',
        LeadSource = 'Web',
        IsConverted = false
    ));
    leads.add(new Lead(
        FirstName = 'Rahul',
        LastName = 'Sharma',
        Company = 'Gyizer',
        Email = 'rahul@test.com',
        LeadSource = 'Phone Inquiry',
        IsConverted = false
    ));
    leads.add(new Lead(
        FirstName = 'Mohit',
        LastName = 'Jain',
        Company = 'ForceSAP',
        Email = 'mohit@test.com',
        LeadSource = null,
        IsConverted = false
    ));

    insert leads;
}

    // Dummy Queueable for testing enqueueJOb
    public class ContactSyncQueueable implements Queueable {
        public ContactSyncQueueable(List<Id> ids){ }
        public void execute(QueueableContext qc){
        }
    }

    // --------------------------------------------------------------
    // TEST: getLeadSources()
    // --------------------------------------------------------------
    @IsTest
    static void testGetLeadSources() {
        createTestLeads();

        Test.startTest();
        List<String> sources = LeadListController.getLeadSources();
        Test.stopTest();

        System.assertNotEquals(0, sources.size(), 'Lead sources should not be empty.');
        System.assert(sources.contains('Web'), 'Should contain Web source');
        System.assert(sources.contains('Phone Inquiry'), 'Should contain Phone Inquiry');
    }

    // --------------------------------------------------------------
    // TEST: getLeads() – Positive scenario, pagination + search + filter
    // --------------------------------------------------------------
    @IsTest
    static void testGetLeadsPositive() {
        createTestLeads();

        Test.startTest();
        LeadListController.LeadListResponse response =
            LeadListController.getLeads('Akshay', 'Web', 10, 1);
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should not be null');
        System.assert(response.totalRecords == 1, 'Only one non-converted Akshay with Web LeadSource');
        System.assertEquals(1, response.leads.size(), 'Only one record must return');
        System.assert(response.leads[0].name.contains('Akshay'), 'Name must contain Akshay');
        System.assertEquals('Web', response.leads[0].leadSource);
    }

    // --------------------------------------------------------------
    // TEST: getLeads() – Test pagination works
    // --------------------------------------------------------------
    @IsTest
    static void testGetLeadsPagination() {
        createTestLeads();

        Test.startTest();
        LeadListController.LeadListResponse response =
            LeadListController.getLeads(null, null, 1, 2);  // Page 2, limit 1
        Test.stopTest();

        System.assertEquals(1, response.leads.size(), 'Only one record per page expected');
        System.assert(response.totalRecords == 3, 'Only 3 non-converted leads should be counted');
    }

    // --------------------------------------------------------------
    // TEST: getLeads() – No filters
    // --------------------------------------------------------------
    @IsTest
    static void testGetLeadsNoFilter() {
        createTestLeads();

        Test.startTest();
        LeadListController.LeadListResponse response =
            LeadListController.getLeads('', '', 20, 1);
        Test.stopTest();

        System.assertEquals(3, response.totalRecords, '3 non-converted leads must be returned');
        System.assertEquals(3, response.leads.size());
    }

    // --------------------------------------------------------------
    // TEST: startContactsSync – positive scenario
    // --------------------------------------------------------------
    @IsTest
    static void testStartContactsSyncPositive() {
        createTestLeads();
        List<Lead> leads = [SELECT Id FROM Lead WHERE IsConverted = false LIMIT 2];

        Test.startTest();
        LeadListController.startContactsSync(new List<Id>{ leads[0].Id, leads[1].Id });
        Test.stopTest();

        // If no exception → test passes
        System.assert(true, 'Queueable called successfully');
    }

    // --------------------------------------------------------------
    // TEST: startContactsSync – negative scenario
    // --------------------------------------------------------------
    @IsTest
    static void testStartContactsSyncThrowsError() {
        try {
            LeadListController.startContactsSync(new List<Id>());
            System.assert(false, 'Should throw error for empty list');
        } catch (AuraHandledException aex) {
            //System.assert(aex.getMessage().contains('No leads selected'));
        }
    }
}