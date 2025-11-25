/**
 * Queueable job that:
 *  - Takes a list of Lead Ids (from the LWC)
 *  - Loads ONLY unconverted leads with email
 *  - Maps them to ContactSyncDTO objects
 *  - Calls Org B via ContactSyncIntegrationService
 */
public with sharing class ContactSyncQueueable
    implements Queueable, Database.AllowsCallouts {

    private final Set<Id> leadIds;

    public ContactSyncQueueable(List<Id> leadIds) {
        this.leadIds = (leadIds == null)
            ? new Set<Id>()
            : new Set<Id>(leadIds);
    }

    public void execute(QueueableContext context) {
        if (leadIds.isEmpty()) {
            return;
        }

        try {
            // 1) Load unconverted leads with Email
            List<Lead> leadsToSync = [
                SELECT Id,
                       FirstName,
                       LastName,
                       Email,
                       Phone,
                       Company
                FROM Lead
                WHERE Id IN :leadIds
                  AND IsConverted = false
                  AND Email != null
            ];

            if (leadsToSync.isEmpty()) {
                System.debug(LoggingLevel.INFO,
                    'ContactSyncQueueable: No unconverted leads with email. leadIds=' + leadIds
                );
                return;
            }

            // 2) Map Leads -> DTOs for Org B
            List<ContactSyncIntegrationService.ContactSyncDTO> dtoList =
                new List<ContactSyncIntegrationService.ContactSyncDTO>();

            for (Lead l : leadsToSync) {
                if (String.isBlank(l.Email)) continue;
                dtoList.add(ContactSyncIntegrationService.fromLead(l));
            }

            if (dtoList.isEmpty()) {
                System.debug(LoggingLevel.INFO,
                    'ContactSyncQueueable: All selected leads had blank emails. leadIds=' + leadIds
                );
                return;
            }

            // If exactly one lead was selected, link it to error log
            Id singleLeadId = (leadIds.size() == 1)
                ? (Id)leadIds.iterator().next()
                : null;

            // 3) Send DTOs to Org B via Named Credential
            ContactSyncIntegrationService.sendContactsToOrgB(dtoList, singleLeadId);

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'ContactSyncQueueable failed. leadIds=' + leadIds +
                ', message=' + ex.getMessage() +
                ', stack=' + ex.getStackTraceString()
            );
        }
    }
}