/**
 * @description Tests for DD_DealDeskBrokerService.
 */
@isTest
private class DD_DealDeskBrokerServiceTest {

    private static final String DEAL_ID = 'ACME-Q4';

    private static DD_DealDeskBrokerService.BrokerResult review(HttpCalloutMock mock, Decimal discount) {
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        DD_DealDeskBrokerService.BrokerResult result = DD_DealDeskBrokerService.reviewDeal(DEAL_ID, discount);
        Test.stopTest();
        return result;
    }

    @isTest
    static void shouldReturnApprovedWithContract_WhenBrokerApproves() {
        DD_DealDeskBrokerService.BrokerResult result =
            review(DD_DealDeskBrokerMock.reply('TASK_STATE_COMPLETED', DD_DealDeskBrokerMock.APPROVED_TEXT), 10);

        Assert.isTrue(result.isSuccess, 'Approved reply should succeed');
        Assert.areEqual(DD_DealDeskBrokerService.DECISION_APPROVED, result.decision, 'Decision should be Approved');
        Assert.areEqual('CTR-ACME-Q4-10', result.contractDraftId, 'Contract draft ID should be extracted');
        Assert.areEqual(DD_DealDeskBrokerMock.APPROVED_TEXT, result.summary, 'Summary should be the full reply text');
    }

    @isTest
    static void shouldSendA2aSendMessage_WhenReviewing() {
        review(DD_DealDeskBrokerMock.reply('TASK_STATE_COMPLETED', DD_DealDeskBrokerMock.APPROVED_TEXT), 10.00);

        HttpRequest sent = DD_DealDeskBrokerMock.lastRequest;
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(sent.getBody());
        Map<String, Object> message = (Map<String, Object>) ((Map<String, Object>) body.get('params')).get('message');
        Map<String, Object> part = (Map<String, Object>) ((List<Object>) message.get('parts'))[0];
        Assert.areEqual('POST', sent.getMethod(), 'Broker call should be a POST');
        Assert.areEqual('1.0', sent.getHeader('A2A-Version'), 'A2A-Version header should be 1.0');
        Assert.areEqual('SendMessage', body.get('method'), 'JSON-RPC method should be SendMessage');
        Assert.areEqual('ROLE_USER', message.get('role'), 'Message role should be ROLE_USER');
        Assert.areEqual('Review deal ACME-Q4 with 10% discount', part.get('text'), 'Message text should name deal and discount');
    }

    @isTest
    static void shouldReturnVpApproval_WhenBrokerNeedsVp() {
        DD_DealDeskBrokerService.BrokerResult result =
            review(DD_DealDeskBrokerMock.reply('TASK_STATE_COMPLETED', DD_DealDeskBrokerMock.VP_TEXT), 20);

        Assert.areEqual(DD_DealDeskBrokerService.DECISION_VP_APPROVAL, result.decision, 'Decision should be VP Approval Required');
        Assert.areEqual('CTR-ACME-Q4-20', result.contractDraftId, 'Pending contract draft ID should be extracted');
    }

    @isTest
    static void shouldReturnNotAllowedWithoutContract_WhenBrokerRejects() {
        DD_DealDeskBrokerService.BrokerResult result =
            review(DD_DealDeskBrokerMock.reply('TASK_STATE_COMPLETED', DD_DealDeskBrokerMock.NOT_ALLOWED_TEXT), 30);

        Assert.isTrue(result.isSuccess, 'Not allowed is still a valid decision');
        Assert.areEqual(DD_DealDeskBrokerService.DECISION_NOT_ALLOWED, result.decision, 'Decision should be Not Allowed');
        Assert.isNull(result.contractDraftId, 'No contract draft when the discount is not allowed');
    }

    @isTest
    static void shouldReturnNeedsInfo_WhenBrokerAsksForInput() {
        DD_DealDeskBrokerService.BrokerResult result =
            review(DD_DealDeskBrokerMock.reply('TASK_STATE_INPUT_REQUIRED', DD_DealDeskBrokerMock.NEED_INFO_TEXT), 10);

        Assert.isTrue(result.isSuccess, 'Input required should be handled as a valid outcome');
        Assert.areEqual(DD_DealDeskBrokerService.DECISION_NEEDS_INFO, result.decision, 'Decision should be Needs Info');
    }

    @isTest
    static void shouldReturnRetryMessage_WhenTaskFailed() {
        DD_DealDeskBrokerService.BrokerResult result = review(DD_DealDeskBrokerMock.reply(
            'TASK_STATE_FAILED', 'The language model service is temporarily unavailable. Please retry.'), 10);

        Assert.isFalse(result.isSuccess, 'Failed task should not succeed');
        Assert.areEqual('TASK_STATE_FAILED', result.taskState, 'Task state should be passed through');
        Assert.isTrue(result.errorMessage.contains('60 seconds'), 'Error should tell the user to retry after 60 seconds');
    }

    @isTest
    static void shouldReturnError_WhenCompletedReplyHasNoDecision() {
        DD_DealDeskBrokerService.BrokerResult result =
            review(DD_DealDeskBrokerMock.reply('TASK_STATE_COMPLETED', 'Something unexpected'), 10);

        Assert.isFalse(result.isSuccess, 'Reply without a decision should not succeed');
        Assert.isNull(result.decision, 'Decision should be empty');
    }

    @isTest
    static void shouldThrow_WhenBrokerReturnsHttpError() {
        Test.setMock(HttpCalloutMock.class, new DD_DealDeskBrokerMock(500, 'error'));
        Test.startTest();
        try {
            DD_DealDeskBrokerService.reviewDeal(DEAL_ID, 10);
            Assert.fail('Expected DealDeskBrokerException for HTTP 500');
        } catch (DD_DealDeskBrokerService.DealDeskBrokerException e) {
            Assert.isTrue(e.getMessage().contains('HTTP 500'), 'Message should mention the HTTP status');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrow_WhenReplyIsUnreadable() {
        Test.setMock(HttpCalloutMock.class, new DD_DealDeskBrokerMock(200, 'not json'));
        Test.startTest();
        try {
            DD_DealDeskBrokerService.reviewDeal(DEAL_ID, 10);
            Assert.fail('Expected DealDeskBrokerException for an unreadable body');
        } catch (DD_DealDeskBrokerService.DealDeskBrokerException e) {
            Assert.isTrue(e.getMessage().contains('Unreadable'), 'Message should say the reply is unreadable');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrow_WhenReplyHasNoTaskStatus() {
        Test.setMock(HttpCalloutMock.class, new DD_DealDeskBrokerMock(200, '{"jsonrpc":"2.0","result":{}}'));
        Test.startTest();
        try {
            DD_DealDeskBrokerService.reviewDeal(DEAL_ID, 10);
            Assert.fail('Expected DealDeskBrokerException when task status is missing');
        } catch (DD_DealDeskBrokerService.DealDeskBrokerException e) {
            Assert.isTrue(e.getMessage().contains('no task status'), 'Message should say task status is missing');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrow_WhenDealIdIsBlank() {
        Test.startTest();
        try {
            DD_DealDeskBrokerService.reviewDeal(' ', 10);
            Assert.fail('Expected DealDeskBrokerException for a blank deal ID');
        } catch (DD_DealDeskBrokerService.DealDeskBrokerException e) {
            Assert.isTrue(e.getMessage().contains('required'), 'Message should say inputs are required');
        }
        Test.stopTest();
    }
}
