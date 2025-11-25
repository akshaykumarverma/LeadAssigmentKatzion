public with sharing class ContactSyncIntegrationService {

    // -------- DTOs (must match OrgB_ContactSyncRest) --------
    public class ContactSyncDTO {
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
        public String accountName;
    }

    public class UpsertResultDTO {
        public String  email;
        public Boolean success;
        public String  errorMessage;
    }

    @TestVisible
    private static final String NC_ENDPOINT = 'callout:OrgB_REST';

    // -------- Helper to map Lead -> DTO --------
    public static ContactSyncDTO fromLead(Lead l) {
        ContactSyncDTO dto = new ContactSyncDTO();
        dto.firstName   = l.FirstName;
        dto.lastName    = l.LastName;
        dto.email       = l.Email;
        dto.phone       = l.Phone;
        dto.accountName = l.Company;   // Lead.Company goes to Account.Name in Org B
        return dto;
    }

    // Overload without Lead reference
    public static void sendContactsToOrgB(List<ContactSyncDTO> dtos) {
        sendContactsToOrgB(dtos, null);
    }

    /**
     * Main send method used by Queueable.
     * @param dtos          DTOs created from Leads
     * @param relatedLeadId optional – if only one lead was selected you can pass it,
     *                      so it is stored in Integration_Error_Log__c.Lead__c
     */
    public static void sendContactsToOrgB(List<ContactSyncDTO> dtos, Id relatedLeadId) {
        if (dtos == null || dtos.isEmpty()) {
            return;
        }

        // Filter out DTOs without email
        List<ContactSyncDTO> filtered = new List<ContactSyncDTO>();
        for (ContactSyncDTO d : dtos) {
            if (d != null && !String.isBlank(d.email)) {
                filtered.add(d);
            }
        }
        if (filtered.isEmpty()) {
            return;
        }

        String requestJson = JSON.serialize(filtered);	
		System.debug('requestJson-->>'+requestJson);
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NC_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(requestJson);

        Http http = new Http();
        HttpResponse res;

        // ---- 1) Callout & transport error logging ----
        try {
            res = http.send(req);
        } catch (Exception ex) {
            logCalloutError(
                'ContactSync Callout Exception',
                relatedLeadId,
                null,
                ex.getMessage(),
                requestJson,
                null
            );
            System.debug('ex cache message-->>'+ex.getMessage());

            return;
        }

        Integer status       = res.getStatusCode();
        String  responseBody = res.getBody();

        // ---- 2) HTTP non-200 ----
        if (status != 200) {
            logCalloutError(
                'ContactSync HTTP ' + String.valueOf(status),
                relatedLeadId,
                null,
                'Non-200 from Org B: ' + res.getStatus(),
                requestJson,
                responseBody
            );
            return;
        }

        // ---- 3) Parse per-record results ----
        List<UpsertResultDTO> results;
        try {
            results = (List<UpsertResultDTO>) JSON.deserialize(
                responseBody,
                List<UpsertResultDTO>.class
            );
        } catch (Exception ex) {
            logCalloutError(
                'ContactSync Response Parse Error',
                relatedLeadId,
                null,
                'Failed to parse Org B response: ' + ex.getMessage(),
                requestJson,
                responseBody
            );
            return;
        }

        if (results == null || results.isEmpty()) {
            return;
        }

        // ---- 4) Log only the failed records into Integration_Error_Log__c ----
        List<Integration_Error_Log__c> logs = new List<Integration_Error_Log__c>();

        for (UpsertResultDTO r : results) {
            if (r == null || r.success == null || r.success) {
                continue; // success – nothing to log
            }

            Integration_Error_Log__c log = new Integration_Error_Log__c();
            log.Name                = 'ContactSync';        // Integration Error Log Name
            log.Status__c           = 'FAILED';
            log.Lead__c             = relatedLeadId;        // only if you pass one
            log.External_Key__c     = r.email;
            log.Error_Message__c    = r.errorMessage;
            log.Request_Payload__c  = requestJson;
            log.Response_Payload__c = JSON.serialize(r);

            logs.add(log);
        }

        if (!logs.isEmpty()) {
            try {
                insert logs;
            } catch (DmlException dmx) {
                System.debug(LoggingLevel.ERROR,
                    'Failed to insert Integration_Error_Log__c: ' + dmx.getMessage());
            }
        }
    }

    // --------- Helper to log top-level callout failures ---------
    private static void logCalloutError(
        String name,
        Id leadId,
        String externalKey,
        String errorMessage,
        String requestPayload,
        String responsePayload
    ) {
        Integration_Error_Log__c log = new Integration_Error_Log__c();
        log.Name                = name;
        log.Status__c           = 'FAILED';
        log.Lead__c             = leadId;
        log.External_Key__c     = externalKey;
        log.Error_Message__c    = errorMessage;
        log.Request_Payload__c  = requestPayload;
        log.Response_Payload__c = responsePayload;

        try {
            insert log;
        } catch (DmlException dmx) {
            System.debug(LoggingLevel.ERROR,
                'Could not save Integration_Error_Log__c: ' + dmx.getMessage());
        }
    }
}