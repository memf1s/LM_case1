public with sharing class RelatedAccountsController {
    // TODO: take Custom Metadata
    private final static Integer MAX_LOOKUP_DEPTH = 50;
    private static final Set<String> COMMON_DOMAINS = new Set<String>{
            'gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com',
            'icloud.com', 'live.com', 'me.com'
    };

    /**
     * @description Return a list of Account records where duplication is suspected based on the Contacts Email address domain name,
     * excludes records that belong to the same hierarchy
     * @param accountId Target Account Id
     *
     * @return Suspected Account Name and shared domain name for each match
     */
    @AuraEnabled(Cacheable=true)
    public static List<AccountInfo> getRelatedAccountsByDomain(Id accountId) {

        // Step 1: Get email domains from contacts related to this account via ACR
        Set<String> domains = getAccountContactsEmailDomains(accountId);
        if (domains.isEmpty()) {
            return new List<AccountInfo>();
        }

        // Step 2: Find candidate accounts via matching contact email domains
        Map<Id, AccountInfo> candidateMap = getDuplicationCandidates(accountId, domains);
        if (candidateMap.isEmpty()) {
            return new List<AccountInfo>();
        }

        // Step 3: Find ultimate parents of target account and all candidates
        Set<Id> allAccountIds = new Set<Id>(candidateMap.keySet());
        allAccountIds.add(accountId);
        Map<Id, Id> candidateRoots = getUltimateParent(allAccountIds);

        // Step 4: Exclude candidates that share the same root
        Id targetAccountRoot = candidateRoots.get(accountId);
        List<AccountInfo> results = new List<AccountInfo>();
        for (Id candidateId : candidateRoots.keySet()) {
            Id candidateAccountRoot = candidateRoots.get(candidateId);
            if (candidateAccountRoot != null && candidateAccountRoot != targetAccountRoot) {
                results.add(candidateMap.get(candidateId));
            }
        }

        return results;
    }

    /**
     * @description Collect unique domain names from Account Contacts Email addresses
     * @param accountId Account Record Id
     *
     * @return List of AccountInfo
     */
    private static Set<String> getAccountContactsEmailDomains(Id accountId) {
        List<AccountContactRelation> acrs = [
                SELECT Contact.Email
                FROM AccountContactRelation
                WHERE AccountId = :accountId
                AND Contact.Email != NULL
        ];

        Set<String> domains = new Set<String>();
        for (AccountContactRelation acr : acrs) {
            String email = acr.Contact.Email;
            if (email.contains('@')) {
                String domain = email.substringAfter('@').toLowerCase();
                if (!isCommonDomain(domain)) {
                    domains.add(domain);
                }
            }
        }

        return domains;
    }

    /**
     * @description Get Account records that share the email domain name with the target Account record
     * @param accountId Target Account Id
     * @param emailDomains List of target Account email domain names
     *
     * @return Map of potential duplicate Account records details by Account Id
     */
    private static Map<Id, AccountInfo> getDuplicationCandidates(Id accountId, Set<String> emailDomains) {
        Set<String> emailLikeConditions = new Set<String>();
        for (String domain : emailDomains) {
            emailLikeConditions.add('%@' + domain);
        }

        List<AccountContactRelation> matchingAcrs = [
                SELECT AccountId, Account.Name, Account.Website,
                        Account.BillingCity, Account.BillingCountry, Contact.Email
                FROM AccountContactRelation
                WHERE AccountId != :accountId
                AND Contact.Email LIKE :emailLikeConditions
        ]; // TODO: introduce limits, we need to understand how many records can be retrieved here

        // Filter by domain match and collect candidate account IDs
        Map<Id, AccountInfo> candidateMap = new Map<Id, AccountInfo>();
        for (AccountContactRelation acr : matchingAcrs) {
            String email = acr.Contact.Email;
            if (!email.contains('@')) continue;
            String domain = email.substringAfter('@').toLowerCase();
            if (emailDomains.contains(domain) && !candidateMap.containsKey(acr.AccountId)) {
                candidateMap.put(acr.AccountId, new AccountInfo(
                        acr.AccountId,
                        acr.Account.Name,
                        domain
                ));
            }
        }

        return candidateMap;
    }

    /**
     * @description Trace Account Hierarchies upwards, find the root parent Account Id for each Account Id provided
     * @param accountIds Starting points for hierarchy scan upwards
     *
     * @return Map of root parent Account Ids by the provided Account Ids
     */
    private static Map<Id, Id> getUltimateParent(Set<Id> accountIds) {
        Map<Id, Id> parentPointer = new Map<Id, Id>();
        Set<Id> toLoad = new Set<Id>(accountIds);
        Set<Id> loaded = new Set<Id>();
        Integer iterationsCount = 0;

        while (!toLoad.isEmpty() && iterationsCount < MAX_LOOKUP_DEPTH) {
            List<Account> batch = [SELECT Id, ParentId FROM Account WHERE Id IN :toLoad];
            toLoad.clear();
            for (Account acc : batch) {
                parentPointer.put(acc.Id, acc.ParentId);
                loaded.add(acc.Id);
                if (acc.ParentId != null && !loaded.contains(acc.ParentId)) {
                    toLoad.add(acc.ParentId);
                }
            }
            iterationsCount++;
        }

        Map<Id, Id> result = new Map<Id, Id>();
        for (Id originId : accountIds) {
            result.put(originId, findRoot(originId, parentPointer));
        }

        return result;
    }

    /**
     * @description Looks for the ultimate parent in the Parent "tree" map
     * @param accountId child Account Id
     * @param parentPointer Map of child to parent Account Ids
     *
     * @return Id of the ultimate parent Account record or furthest record in case of a loop
     */
    private static Id findRoot(Id accountId, Map<Id, Id> parentPointer) {
        Set<Id> visited = new Set<Id>();
        Id cursor = accountId;

        while (cursor != null) {
            if (visited.contains(cursor)) {
                System.debug(LoggingLevel.WARN, 'Loop detected at: ' + cursor); // TODO: come up with better way to notify about limit reached and possibly incomplete data
                break;
            }
            visited.add(cursor);

            Id parent = parentPointer.get(cursor);
            if (parent == null) {
                return cursor;
            }
            cursor = parent;
        }

        return cursor;
    }

    private static Boolean isCommonDomain(String domain) {
        return COMMON_DOMAINS.contains(domain);
    }

    public class AccountInfo {
        @AuraEnabled
        public Id accountId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String matchedDomain;

        public AccountInfo(Id accountId, String name, String matchedDomain) {
            this.accountId = accountId;
            this.name = name;
            this.matchedDomain = matchedDomain;
        }
    }
}