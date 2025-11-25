/**
 * LeadListController
 * -------------------
 * - Provides paginated, searchable, filterable Lead data for LWC.
 * - Starts async Contact sync (Queueable) based on selected Leads.
 *
 * Design:
 * - with sharing to respect org sharing rules.
 * - Dynamic SOQL with bind variables (no string concatenated values).
 * - Server-side pagination using LIMIT + OFFSET.
 */
public with sharing class LeadListController {

    /**
     * DTO for Lead rows in LWC datatable.
     */
    public class LeadListDTO {
        @AuraEnabled public Id    leadId;
        @AuraEnabled public String name;
        @AuraEnabled public String company;
        @AuraEnabled public String email;
        @AuraEnabled public String leadSource;
    }

    /**
     * Wrapper for response to LWC (records + total count).
     */
    public class LeadListResponse {
        @AuraEnabled public List<LeadListDTO> leads;
        @AuraEnabled public Integer totalRecords;
    }

    /**
     * Returns paginated Leads with optional search + LeadSource filter.
     *
     * @param searchKey         Search text (FirstName/LastName contains).
     * @param leadSourceFilter  LeadSource exact match ('' or null = all).
     * @param pageSize          Page size (default 20).
     * @param pageNumber        1-based page index (default 1).
     */
    @AuraEnabled(cacheable=true)
    public static LeadListResponse getLeads(
        String searchKey,
        String leadSourceFilter,
        Integer pageSize,
        Integer pageNumber
    ) {
        // ---- Normalize paging ----
        if (pageSize == null || pageSize <= 0) {
            pageSize = 20;
        }
        if (pageNumber == null || pageNumber < 1) {
            pageNumber = 1;
        }
        Integer offsetVal = (pageNumber - 1) * pageSize;

        // ---- Prepare filter values ----
        String likeKey = null;
        if (String.isNotBlank(searchKey)) {
            likeKey = '%' + searchKey.trim() + '%';
        }
        Boolean hasLike   = (likeKey != null);
        Boolean hasSource = !String.isBlank(leadSourceFilter);

        // ---- Build WHERE clause dynamically with bind variables ----
        String baseFrom = ' FROM Lead WHERE IsConverted = false';
        List<String> extraConds = new List<String>();

        if (hasLike) {
            extraConds.add('(FirstName LIKE :likeKey OR LastName LIKE :likeKey)');
        }
        if (hasSource) {
            extraConds.add('LeadSource = :leadSourceFilter');
        }

        if (!extraConds.isEmpty()) {
            baseFrom += ' AND ' + String.join(extraConds, ' AND ');
        }

        // ---- Count query (no OFFSET/LIMIT) ----
        String countQuery = 'SELECT COUNT()' + baseFrom;
        Integer totalRecordsNumber = (Integer) Database.countQuery(countQuery);

        // ---- Data query with LIMIT + OFFSET ----
        String dataQuery =
            'SELECT Id, FirstName, LastName, Company, Email, LeadSource' +
            baseFrom +
            ' ORDER BY CreatedDate DESC' +
            ' LIMIT :pageSize OFFSET :offsetVal';

        List<Lead> leadRecords = Database.query(dataQuery);

        // ---- Map to DTOs ----
        List<LeadListDTO> dtos = new List<LeadListDTO>();
        for (Lead l : leadRecords) {
            LeadListDTO dto = new LeadListDTO();
            dto.leadId     = l.Id;
            dto.name       = ((l.FirstName != null) ? l.FirstName + ' ' : '') + l.LastName;
            dto.company    = l.Company;
            dto.email      = l.Email;
            dto.leadSource = l.LeadSource;
            dtos.add(dto);
        }

        // ---- Build response ----
        LeadListResponse resp = new LeadListResponse();
        resp.leads = dtos;
        resp.totalRecords = totalRecordsNumber;

        return resp;
    }

    /**
     * Returns distinct LeadSource values for use in filter combobox.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getLeadSources() {
        List<String> sources = new List<String>();

        for (AggregateResult ar : [
            SELECT LeadSource src
            FROM Lead
            WHERE IsConverted = false
            AND LeadSource != null
            GROUP BY LeadSource
            ORDER BY LeadSource
        ]) {
            sources.add((String) ar.get('src'));
        }

        return sources;
    }

    /**
     * Starts async sync process for given Lead Ids.
     * Queueable (ContactSyncQueueable) will:
     *  - Convert Leads to Contacts.
     *  - Call Org B via Named Credential.
     */
    @AuraEnabled
    public static void startContactsSync(List<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            throw new AuraHandledException('No leads selected for sync.');
        }

        // NOTE: ContactSyncQueueable must exist – we’ll build it next.
       System.enqueueJob(new ContactSyncQueueable(leadIds));
    }
}