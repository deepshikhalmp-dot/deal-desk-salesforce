/**
 * @description Tests for the DD_ReviewDealDiscountAction invocable action.
 * The action uses USER_MODE, so every test runs as a Standard User with the DD_Deal_Desk_User
 * permission set (never as the deploying admin), and the test Opportunities are owned by that user.
 * Bulk 251-record testing does not apply: each request is one HTTP callout (limit 100 per transaction),
 * and the action is called one deal at a time by Agentforce.
 */
@isTest
private class DD_ReviewDealDiscountActionTest {

    @TestSetup
    static void setupTestData() {
        User dealDeskUser = DD_TestDataFactory.createDealDeskUser();
        DD_TestDataFactory.createUserWithoutDealDeskAccess();
        DD_TestDataFactory.createDealDeskOpportunities(1, true, dealDeskUser.Id);
    }

    private static Opportunity getOpportunity() {
        return [SELECT Id, DD_Deal_ID__c FROM Opportunity WHERE Name = 'DD Test Opportunity 0' LIMIT 1];
    }

    private static DD_ReviewDealDiscountAction.Request buildRequest(Id opportunityId, String dealId, Decimal discount) {
        DD_ReviewDealDiscountAction.Request req = new DD_ReviewDealDiscountAction.Request();
        req.opportunityId = opportunityId;
        req.dealId = dealId;
        req.discountPercent = discount;
        return req;
    }

    private static DD_ReviewDealDiscountAction.Response run(DD_ReviewDealDiscountAction.Request req) {
        return runAs(DD_TestDataFactory.getDealDeskUser(), req);
    }

    private static DD_ReviewDealDiscountAction.Response runAs(User runningUser, DD_ReviewDealDiscountAction.Request req) {
        List<DD_ReviewDealDiscountAction.Response> responses;
        System.runAs(runningUser) {
            Test.startTest();
            responses = DD_ReviewDealDiscountAction.execute(new List<DD_ReviewDealDiscountAction.Request>{ req });
            Test.stopTest();
        }
        return responses[0];
    }

    @isTest
    static void shouldSaveDecisionOnOpportunity_WhenDealIdComesFromOpportunity() {
        Opportunity opp = getOpportunity();
        Test.setMock(HttpCalloutMock.class,
            DD_DealDeskBrokerMock.reply('TASK_STATE_COMPLETED', DD_DealDeskBrokerMock.VP_TEXT));

        DD_ReviewDealDiscountAction.Response res = run(buildRequest(opp.Id, null, 20));

        Opportunity saved = [
            SELECT DD_Decision__c, DD_Requested_Discount__c, DD_Contract_Draft_Id__c, DD_Deal_Desk_Summary__c
            FROM Opportunity WHERE Id = :opp.Id
        ];
        Assert.isTrue(res.isSuccess, 'Review should succeed');
        Assert.isNull(res.errorMessage, 'Saving the decision should not report an error');
        Assert.areEqual('VP Approval Required', saved.DD_Decision__c, 'Decision should be saved on the Opportunity');
        Assert.areEqual(20, saved.DD_Requested_Discount__c, 'Requested discount should be saved');
        Assert.areEqual('CTR-ACME-Q4-20', saved.DD_Contract_Draft_Id__c, 'Contract draft ID should be saved');
        Assert.areEqual(DD_DealDeskBrokerMock.VP_TEXT, saved.DD_Deal_Desk_Summary__c, 'Full summary should be saved');
        Assert.isTrue(DD_DealDeskBrokerMock.lastRequest.getBody().contains('ACME-Q4'), 'Deal ID should come from the Opportunity');
    }

    @isTest
    static void shouldUseGivenDealId_WhenNoOpportunity() {
        Test.setMock(HttpCalloutMock.class,
            DD_DealDeskBrokerMock.reply('TASK_STATE_COMPLETED', DD_DealDeskBrokerMock.NOT_ALLOWED_TEXT));

        DD_ReviewDealDiscountAction.Response res = run(buildRequest(null, 'GLOBEX-Q4', 30));

        Assert.isTrue(res.isSuccess, 'Review should succeed');
        Assert.areEqual('Not Allowed', res.decision, 'Decision should be Not Allowed');
        Assert.isNull(res.contractDraftId, 'No contract draft when not allowed');
        Assert.isTrue(DD_DealDeskBrokerMock.lastRequest.getBody().contains('GLOBEX-Q4'), 'Given deal ID should be sent');
    }

    @isTest
    static void shouldReturnMissingDealIdError_WhenNoDealIdAvailable() {
        DD_ReviewDealDiscountAction.Response res = run(buildRequest(null, null, 10));

        Assert.isFalse(res.isSuccess, 'Review without a deal ID should fail');
        Assert.areEqual('MISSING_DEAL_ID', res.errorType, 'Error type should be MISSING_DEAL_ID');
    }

    @isTest
    static void shouldReturnError_WhenBrokerCallFails() {
        Test.setMock(HttpCalloutMock.class, new DD_DealDeskBrokerMock(503, 'unavailable'));

        DD_ReviewDealDiscountAction.Response res = run(buildRequest(null, 'ACME-Q4', 10));

        Assert.isFalse(res.isSuccess, 'Broker HTTP error should fail the review');
        Assert.isTrue(res.errorMessage.contains('HTTP 503'), 'Error message should mention the HTTP status');
    }

    @isTest
    static void shouldNotUpdateOpportunity_WhenTaskFailed() {
        Opportunity opp = getOpportunity();
        Test.setMock(HttpCalloutMock.class, DD_DealDeskBrokerMock.reply(
            'TASK_STATE_FAILED', 'The language model service is temporarily unavailable. Please retry.'));

        DD_ReviewDealDiscountAction.Response res = run(buildRequest(opp.Id, null, 10));

        Opportunity saved = [SELECT DD_Decision__c FROM Opportunity WHERE Id = :opp.Id];
        Assert.isFalse(res.isSuccess, 'Failed broker task should fail the review');
        Assert.isNull(saved.DD_Decision__c, 'Opportunity should not be updated when the review failed');
        Assert.areEqual('BROKER_TASK_TASK_STATE_FAILED', res.errorType, 'Error type should carry the task state');
    }

    @isTest
    static void shouldReturnPermissionError_WhenUserLacksDealDeskAccess() {
        Opportunity opp = getOpportunity();

        DD_ReviewDealDiscountAction.Response res =
            runAs(DD_TestDataFactory.getUserWithoutDealDeskAccess(), buildRequest(opp.Id, null, 10));

        Assert.isFalse(res.isSuccess, 'Review should fail when the user cannot read the Deal Desk fields');
        Assert.areEqual('OPPORTUNITY_NOT_ACCESSIBLE', res.errorType, 'Error type should be OPPORTUNITY_NOT_ACCESSIBLE');
        Assert.isTrue(res.errorMessage.contains(DD_TestDataFactory.DEAL_DESK_PERMSET),
            'Error message should name the permission set to assign');
        Assert.isNull(DD_DealDeskBrokerMock.lastRequest, 'Broker should not be called without a deal ID');
    }

    @isTest
    static void shouldReturnDecisionWithoutSaving_WhenUserLacksAccessButGivesDealId() {
        Opportunity opp = getOpportunity();
        Test.setMock(HttpCalloutMock.class,
            DD_DealDeskBrokerMock.reply('TASK_STATE_COMPLETED', DD_DealDeskBrokerMock.APPROVED_TEXT));

        DD_ReviewDealDiscountAction.Response res =
            runAs(DD_TestDataFactory.getUserWithoutDealDeskAccess(), buildRequest(opp.Id, 'ACME-Q4', 10));

        Opportunity saved = [SELECT DD_Decision__c FROM Opportunity WHERE Id = :opp.Id];
        Assert.isTrue(res.isSuccess, 'Decision should still be returned');
        Assert.areEqual('Approved', res.decision, 'Decision should be Approved');
        Assert.isTrue(res.errorMessage.startsWith('Decision returned, but it was not saved on the Opportunity'),
            'Error message should say the decision was not saved');
        Assert.isNull(saved.DD_Decision__c, 'Opportunity should not be updated');
    }

    @isTest
    static void shouldReturnNotAccessibleError_WhenOpportunityNotFound() {
        Opportunity opp = getOpportunity();
        Id deletedOpportunityId = opp.Id;
        delete opp;

        DD_ReviewDealDiscountAction.Response res = run(buildRequest(deletedOpportunityId, null, 10));

        Assert.isFalse(res.isSuccess, 'Review should fail for a missing Opportunity');
        Assert.areEqual('OPPORTUNITY_NOT_ACCESSIBLE', res.errorType, 'Error type should be OPPORTUNITY_NOT_ACCESSIBLE');
        Assert.isTrue(res.errorMessage.contains('not found or is not shared'),
            'Error message should say the Opportunity is not found or not shared');
    }
}
