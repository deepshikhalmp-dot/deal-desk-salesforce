/**
 * Calls the MuleSoft Agent Fabric Deal Desk broker (A2A v1.0 JSON-RPC SendMessage)
 * and turns its reply into a structured Deal Desk result.
 * The broker consults the Pricing, Credit and Contract agents; the customer PAN in the
 * credit report is already masked by an Agent Fabric gateway policy.
 */
public with sharing class DD_DealDeskBrokerService {

    @TestVisible
    private static final String BROKER_ENDPOINT =
        'https://agent-network-shared-gw-f9e1w3.5sc6y6-1.usa-e2.cloudhub.io/deal_desk_broker/';
    private static final Integer TIMEOUT_MS = 120000;

    public static final String DECISION_APPROVED = 'Approved';
    public static final String DECISION_VP_APPROVAL = 'VP Approval Required';
    public static final String DECISION_NOT_ALLOWED = 'Not Allowed';
    public static final String DECISION_NEEDS_INFO = 'Needs Info';

    private static final String STATE_COMPLETED = 'TASK_STATE_COMPLETED';
    private static final String STATE_INPUT_REQUIRED = 'TASK_STATE_INPUT_REQUIRED';
    private static final String RETRY_MESSAGE =
        'The Deal Desk language model is busy (Gemini free tier). Please wait about 60 seconds and ask again.';
    private static final Pattern CONTRACT_ID_PATTERN = Pattern.compile('CTR-[A-Z0-9-]+');

    /**
     * Structured result of one Deal Desk review.
     */
    public class BrokerResult {
        public Boolean isSuccess = false;
        public String decision;
        public String contractDraftId;
        public String summary;
        public String taskState;
        public String errorMessage;
    }

    /**
     * Raised when the broker cannot be reached or returns an unreadable reply.
     */
    public class DealDeskBrokerException extends Exception {}

    /**
     * Asks the Deal Desk broker to review a discount on a deal.
     * @param dealId Deal Desk deal ID, for example ACME-Q4
     * @param discountPercent Requested discount in percent, for example 20
     * @return BrokerResult with decision, contract draft ID and the full reply text
     * @throws DealDeskBrokerException when the broker call fails or the reply cannot be parsed
     * @example
     * DD_DealDeskBrokerService.BrokerResult r = DD_DealDeskBrokerService.reviewDeal('ACME-Q4', 20);
     */
    public static BrokerResult reviewDeal(String dealId, Decimal discountPercent) {
        if (String.isBlank(dealId) || discountPercent == null) {
            throw new DealDeskBrokerException('Deal ID and discount percent are required.');
        }
        String message = 'Review deal ' + dealId.trim() + ' with '
            + discountPercent.stripTrailingZeros().toPlainString() + '% discount';
        HttpResponse response = sendMessage(message);
        return parseReply(response.getBody());
    }

    private static HttpResponse sendMessage(String text) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(BROKER_ENDPOINT);
        request.setMethod('POST');
        request.setTimeout(TIMEOUT_MS);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('A2A-Version', '1.0');
        request.setBody(buildRequestBody(text));
        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (CalloutException e) {
            throw new DealDeskBrokerException('Could not reach the Deal Desk broker.', e);
        }
        if (response.getStatusCode() != 200) {
            throw new DealDeskBrokerException(
                'Deal Desk broker returned HTTP ' + response.getStatusCode() + '.');
        }
        return response;
    }

    @TestVisible
    private static String buildRequestBody(String text) {
        Map<String, Object> part = new Map<String, Object>{ 'text' => text };
        Map<String, Object> message = new Map<String, Object>{
            'messageId' => newUuid(),
            'role' => 'ROLE_USER',
            'parts' => new List<Object>{ part }
        };
        Map<String, Object> body = new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id' => newUuid(),
            'method' => 'SendMessage',
            'params' => new Map<String, Object>{ 'message' => message }
        };
        return JSON.serialize(body);
    }

    @TestVisible
    private static BrokerResult parseReply(String responseBody) {
        Map<String, Object> status;
        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            Map<String, Object> result = (Map<String, Object>) root.get('result');
            Map<String, Object> task = (Map<String, Object>) result?.get('task');
            status = (Map<String, Object>) task?.get('status');
        } catch (Exception e) {
            throw new DealDeskBrokerException('Unreadable reply from the Deal Desk broker.', e);
        }
        if (status == null) {
            throw new DealDeskBrokerException('Deal Desk broker reply has no task status.');
        }

        BrokerResult outcome = new BrokerResult();
        outcome.taskState = (String) status.get('state');
        outcome.summary = extractText(status);

        if (outcome.taskState == STATE_COMPLETED) {
            outcome.decision = toDecision(outcome.summary);
            outcome.contractDraftId = extractContractId(outcome.summary, outcome.decision);
            outcome.isSuccess = outcome.decision != null;
            if (!outcome.isSuccess) {
                outcome.errorMessage = 'Deal Desk reply did not contain a decision.';
            }
        } else if (outcome.taskState == STATE_INPUT_REQUIRED) {
            outcome.decision = DECISION_NEEDS_INFO;
            outcome.isSuccess = true;
        } else {
            outcome.errorMessage = RETRY_MESSAGE;
        }
        return outcome;
    }

    private static String extractText(Map<String, Object> status) {
        Map<String, Object> message = (Map<String, Object>) status.get('message');
        List<Object> parts = (List<Object>) message?.get('parts');
        if (parts == null || parts.isEmpty()) {
            return null;
        }
        return (String) ((Map<String, Object>) parts[0]).get('text');
    }

    private static String toDecision(String replyText) {
        String upper = replyText?.toUpperCase() ?? '';
        if (upper.contains('DEAL DESK DECISION: VP APPROVAL REQUIRED')) {
            return DECISION_VP_APPROVAL;
        }
        if (upper.contains('DEAL DESK DECISION: NOT ALLOWED')) {
            return DECISION_NOT_ALLOWED;
        }
        if (upper.contains('DEAL DESK DECISION: APPROVED')) {
            return DECISION_APPROVED;
        }
        return null;
    }

    private static String extractContractId(String replyText, String decision) {
        if (String.isBlank(replyText) || decision == DECISION_NOT_ALLOWED) {
            return null;
        }
        Matcher match = CONTRACT_ID_PATTERN.matcher(replyText);
        return match.find() ? match.group() : null;
    }

    private static String newUuid() {
        return UUID.randomUUID().toString();
    }
}
