public with sharing class TransactionController {
    // Labels, TODO: use Custom Labels for multilingual support
    private final static String ERROR_ACCOUNT_ID_INVALID = 'Account record Id is missing or invalid.';
    private final static String ERROR_EXTERNAL_ID_INVALID = 'Customer External Id is outside bounds.';
    private final static String ERROR_START_DATE_REQUIRED = 'Start Date is required.';

    /**
     * Fetches transactions from the BSS API for the given Salesforce Account.
     *
     * @param accountId Salesforce Account record Id
     * @param startDate ISO-8601 date-time string
     * @param endDate ISO-8601 date-time string
     * @return List of TransactionDTO wrappers
     */
    @AuraEnabled
    public static TransactionService.TransactionsResponseDTO getAccountTransactions(String accountId, String startDate, String endDate) {
        if (String.isBlank(accountId) || !isValidId(accountId)) {
            throw new AuraHandledException(ERROR_ACCOUNT_ID_INVALID);
        }
        if (String.isBlank(startDate)) {
            throw new AuraHandledException(ERROR_START_DATE_REQUIRED);
        }
        try {
            Integer customerId = getAccountExternalId(Id.valueOf(accountId));
            Datetime startDatetime = (Datetime) JSON.deserialize('"' + startDate + '"', Datetime.class);
            Datetime endDatetime = String.isNotBlank(endDate)
                    ? (Datetime) JSON.deserialize('"' + endDate + '"', Datetime.class)
                    : null;

            TransactionService.TransactionsResponseDTO trDto = TransactionService.getTransactionDetails(customerId, startDatetime, endDatetime);
            System.debug(trDto);
            return trDto;
        } catch(Exception ex) {
            // TODO: Log errors
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * @description Query External Customer Id assigned to the account
     * @param accountId Account Record Id
     *
     * @return External Customer Id
     */
    private static Integer getAccountExternalId(Id accountId) {
        Account account = [
                SELECT Customer_Id__c
                FROM Account
                WHERE Id = :accountId
                WITH SECURITY_ENFORCED
                LIMIT 1
        ];
        if (account == null) {
            throw new AuraHandledException('Account not found: ' + accountId);
        }

        return toIntegerSafe(account.Customer_Id__c);
    }


    private static Boolean isValidId(String s) {
        if (String.isBlank(s)) return false;
        try {
            Id.valueOf(s.trim());
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static Integer toIntegerSafe(Decimal d) {
        if (d == null) return null;

        if (d < 0 || d > 2147483647) {
            throw new AuraHandledException(ERROR_EXTERNAL_ID_INVALID);
        }
        return d.intValue();
    }

}