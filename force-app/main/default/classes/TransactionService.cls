public with sharing class TransactionService {
    private final static Boolean isDemo = true;

    // Labels, TODO: use Custom Labels for multilingual support
    private final static String ERROR_MISSING_ARGUMENTS = 'Mandatory parameters are missing. Please check your input.';
    private final static String ERROR_SERVICE_UNAVAILABLE = 'Could not reach the Transaction API. Please try again later.';
    private final static String ERROR_AUTH_FAILED = 'Authentication failed. Please check the Named Credential configuration.';
    private final static String ERROR_SERVICE_NOT_FOUND = 'Request Failed. Remote service not found.';
    private final static String ERROR_UNEXPECTED_RESPONSE = 'Transaction API returned an unexpected status: ';
    private final static String ERROR_INVALID_JSON = 'Failed to parse API response: ';

    // Metadata linkage, TODO: use Custom Metadata
    private final static String NAMED_CREDENTIALS_NAME = 'LinkBss';
    private final static String endpointPath = '/api/transactions';

    /**
     * @description Fetch Customer transaction records from LinkBss API
     * @param customerId External Customer Id
     * @param startDate Fetch period start date
     * @param endDate Fetch period end date
     *
     * @return API Response DTO
     */
    public static TransactionsResponseDTO getTransactionDetails(Integer customerId, Datetime startDate, Datetime endDate) {
        String requestUrl = 'callout:' + NAMED_CREDENTIALS_NAME + endpointPath;
        requestUrl += new TransactionsRequestDTO(customerId, startDate, endDate).getQueryParamString();

        TransactionsResponseDTO trDTO;
        if (isDemo) {
            trDTO = getDemoDataFromResource(customerId.toString());
        } else {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(requestUrl);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(5000);

            HttpResponse res;
            try {
                res = new Http().send(req);
            } catch (System.CalloutException ce) {
                throw new TransactionServiceException(ERROR_SERVICE_UNAVAILABLE);
            }

            Integer status = res.getStatusCode();
            if (status == 401 || status == 403) {
                throw new TransactionServiceException(ERROR_AUTH_FAILED);
            }
            if (status == 404) {
                throw new TransactionServiceException(ERROR_SERVICE_NOT_FOUND);
            }
            if (status != 200) {
                throw new TransactionServiceException(ERROR_UNEXPECTED_RESPONSE + status + '. ' + res.getBody());
            }

            trDTO = new TransactionsResponseDTO(res.getBody());
        }

        return trDTO;
    }

    /**
     * @description Load JSON Data from Static resource to showcase the UI behavior
     * @param customerId External Id
     *
     * @return Dummy API Response
     */
    private static TransactionsResponseDTO getDemoDataFromResource(String customerId) {
        StaticResource sr = [
                SELECT Body
                FROM StaticResource
                WHERE Name = 'LinkBssDummyData'
                LIMIT 1
        ];
        // Convert body to string and deserialize
        String resourceJsonBody = sr.Body.toString();
        List<Object> dummyResponseList = (List<Object>) JSON.deserializeUntyped(resourceJsonBody);
        for(Object dummyResponse : dummyResponseList) {
            Map<String, Object> responseMap = (Map<String, Object>) dummyResponse;
            TransactionsResponseDTO trDto = new TransactionsResponseDTO(responseMap);
            if(trDto.customerId == customerId) {
                return trDto;
            }
        }

        return null;
    }

    private class TransactionsRequestDTO {
        private final Integer customerId;
        private final String startDate;
        private final String endDate;
        private final String PARAM_DATETIME_FORMAT = 'yyyy-MM-dd\'TT\'HH:mm:ss\'Z\'';

        private TransactionsRequestDTO(Integer customerId, Datetime startDate, Datetime endDate) {
            this.customerId = customerId;
            this.startDate = startDate != null
                    ? startDate.formatGmt(PARAM_DATETIME_FORMAT)
                    : null;
            this.endDate = endDate != null
                    ? endDate.formatGmt(PARAM_DATETIME_FORMAT)
                    : null;
        }

        private String getQueryParamString() {
            if(customerId == null || String.isBlank(startDate)) {
                throw new TransactionServiceException(ERROR_MISSING_ARGUMENTS);
            }
            String paramString = 'customerId=' + customerId;
            paramString += '&startDate=' +  EncodingUtil.urlEncode(startDate, 'UTF-8');
            paramString += (endDate != null)
                    ? '&endDate=' +  EncodingUtil.urlEncode(endDate, 'UTF-8')
                    : '';

            return paramString;
        }
    }

    public class TransactionsResponseDTO {
        @AuraEnabled
        public String customerId;
        @AuraEnabled
        public List<TransactionDetailsDTO> transactions;

        /**
         * @param responseBody Transaction API Response, JSON body
         */
        public TransactionsResponseDTO(String responseBody) {
            Map<String, Object> responseMap;
            try {
                responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
                init(responseMap);
            } catch (JSONException ex) {
                throw new TransactionServiceException(ERROR_INVALID_JSON + ex.getMessage());
            }
        }

        /**
         * @param responseMap Transaction API Response, JSON Deserialized untyped
         */
        public TransactionsResponseDTO(Map<String, Object> responseMap) {
            init(responseMap);
        }

        private void init(Map<String, Object> responseMap) {
            this.customerId = responseMap.get('customerId')?.toString();
            this.transactions = new List<TransactionDetailsDTO>();
            try {
                List<Object> transactionsRaw = (List<Object>) responseMap.get('transactions');
                if (transactionsRaw != null) {
                    for (Object item : transactionsRaw) {
                        Map<String, Object> itemMap = (Map<String, Object>) item;
                        transactions.add(new TransactionDetailsDTO(itemMap));
                    }
                }
            } catch(TypeException ex) {
                throw new TransactionServiceException(ERROR_INVALID_JSON + ex.getMessage());
            }
        }
    }

    public class TransactionDetailsDTO {
        @AuraEnabled
        public String transactionId;
        @AuraEnabled
        public Integer messageParts;
        @AuraEnabled
        public String accountId;
        @AuraEnabled
        public Datetime transactionDate;

        public TransactionDetailsDTO(Map<String, Object> detailsMap) {
            try {
                this.transactionId = detailsMap.get('transactionId')?.toString();
                String messagePartsStr = detailsMap.get('messageparts')?.toString();
                this.messageParts = messagePartsStr != null && messagePartsStr.isNumeric()
                        ? Integer.valueOf(messagePartsStr)
                        : null;
                this.accountId = detailsMap.get('accountId')?.toString();
                String dateStr = detailsMap.get('date')?.toString();
                if (String.isNotBlank(dateStr)) {
                    String normalisedDateStr = dateStr.replace('TT', ' ').removeEnd('Z');
                    this.transactionDate = Datetime.valueOfGmt(normalisedDateStr);
                }
            } catch(TypeException ex) {
                throw new TransactionServiceException(ERROR_INVALID_JSON + ex.getMessage());
            }
        }
    }

    public class TransactionServiceException extends Exception {}
}