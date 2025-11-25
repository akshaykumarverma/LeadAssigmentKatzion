@RestResource(urlMapping='/OrgAContacts')
global with sharing class OrgA_ContactSyncRest {

    // ---------------- DTOs from Org A ----------------
    global class ContactSyncDTO {
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
        public String accountName;
    }

    global class UpsertResultDTO {
        public String  email;
        public Boolean success;
        public String  errorMessage;
    }

    @HttpPost
    global static void upsertContacts() {
        RestRequest req = RestContext.request;
        String rawBody = (req.requestBody == null)
            ? null
            : req.requestBody.toString();

        System.debug(LoggingLevel.INFO,
            'OrgA_ContactSyncRest RAW BODY = ' + rawBody);

        if (String.isBlank(rawBody)) {
            setErrorResponse(400, 'Empty request body.');
            return;
        }

        // 1) Deserialize JSON array
        List<ContactSyncDTO> incoming;
        try {
            incoming = (List<ContactSyncDTO>) JSON.deserialize(
                rawBody,
                List<ContactSyncDTO>.class
            );
        } catch (Exception e) {
            setErrorResponse(400, 'Invalid JSON: ' + e.getMessage());
            return;
        }

        if (incoming == null || incoming.isEmpty()) {
            setErrorResponse(400, 'No contacts provided in request body.');
            return;
        }

        // 2) Collect emails & account names
        Set<String> emails       = new Set<String>();
        Set<String> accountNames = new Set<String>();

        for (ContactSyncDTO dto : incoming) {
            if (dto == null) continue;

            if (!String.isBlank(dto.email)) {
                emails.add(dto.email.trim().toLowerCase());
            }
            if (!String.isBlank(dto.accountName)) {
                accountNames.add(dto.accountName.trim());
            }
        }

        if (emails.isEmpty()) {
            setErrorResponse(400, 'No valid emails provided.');
            return;
        }

        // 3) Load Accounts by Name
        Map<String, Account> accountsByName = new Map<String, Account>();
        if (!accountNames.isEmpty()) {
            for (Account acc : [
                SELECT Id, Name
                FROM Account
                WHERE Name IN :accountNames
            ]) {
                accountsByName.put(acc.Name, acc);
            }
        }

        // 4) Load existing Contacts by email
        Map<String, Contact> contactsByEmail = new Map<String, Contact>();
        for (Contact c : [
            SELECT Id, Email, FirstName, LastName, Phone, AccountId
            FROM Contact
            WHERE Email IN :emails
        ]) {
            if (c.Email != null) {
                contactsByEmail.put(c.Email.trim().toLowerCase(), c);
            }
        }

        // 5) Build Contacts to upsert
        List<Contact> contactsToUpsert = new List<Contact>();

        for (ContactSyncDTO dto : incoming) {
            if (dto == null) continue;
            if (String.isBlank(dto.email)) continue;

            String emailKey = dto.email.trim().toLowerCase();
            Contact c;

            if (contactsByEmail.containsKey(emailKey)) {
                c = contactsByEmail.get(emailKey);
            } else {
                c = new Contact();
                c.Email = dto.email.trim();
            }

            c.FirstName = dto.firstName;
            c.LastName  = dto.lastName;
            c.Phone     = dto.phone;

            if (!String.isBlank(dto.accountName)) {
                Account acc = accountsByName.get(dto.accountName.trim());
                if (acc != null) {
                    c.AccountId = acc.Id;
                }
            }

            contactsToUpsert.add(c);
        }

        if (contactsToUpsert.isEmpty()) {
            setErrorResponse(400, 'No valid contacts to upsert.');
            return;
        }
		
system.debug('contactsToUpsert-->0'+contactsToUpsert);        // 6) Upsert with partial success
        Database.UpsertResult[] dmlResults;
        try {
            dmlResults = Database.upsert(contactsToUpsert, false); // allOrNone=false
        } catch (DmlException e) {
            setErrorResponse(500, 'DML error during upsert: ' + e.getMessage());
system.debug('DML e.getMessage()-->0'+e.getMessage());        // 6) Upsert with partial success

            return;
        }

        // 7) Build per-record response
        List<UpsertResultDTO> resultDtos = new List<UpsertResultDTO>();

        for (Integer i = 0; i < dmlResults.size(); i++) {
            Database.UpsertResult sr = dmlResults[i];
            Contact c = contactsToUpsert[i];

            UpsertResultDTO r = new UpsertResultDTO();
            r.email = c.Email;

            if (sr.isSuccess()) {
                r.success = true;
                r.errorMessage = null;
                System.debug('Rrcords contact email '+ c.Email);
            } else {
                r.success = false;
                String msg = '';
                for (Database.Error e : sr.getErrors()) {
                    msg += e.getStatusCode() + ': ' + e.getMessage() + ' ';
					
                }
                r.errorMessage = msg.trim();
                System.debug('r.errorMessage '+ r.errorMessage);

            }

            resultDtos.add(r);
        }

        // 8) Return JSON array of upsert results
        RestContext.response.statusCode = 200;
        RestContext.response.responseBody =
            Blob.valueOf(JSON.serialize(resultDtos));
    }

    private static void setErrorResponse(Integer statusCode, String message) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.responseBody = Blob.valueOf(message);
        System.debug(LoggingLevel.ERROR,
            'OrgA_ContactSyncRest error. code=' + statusCode +
            ', msg=' + message);
    }
}