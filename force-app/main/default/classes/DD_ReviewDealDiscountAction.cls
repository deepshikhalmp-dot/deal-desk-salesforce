/**
 * Invocable action "Review Deal Discount" for Agentforce and Flow.
 * Sends a discount request to the Agent Fabric Deal Desk broker and, when an
 * Opportunity is given, stores the decision on that Opportunity.
 */
public with sharing class DD_ReviewDealDiscountAction {

    private static final String DEAL_DESK_PERMISSION_SET = 'DD_Deal_Desk_User';

    /**
     * Reviews a requested discount with the Deal Desk broker.
     * @param requests Opportunity and/or deal ID plus the requested discount percent
     * @return One Response per request with the decision, contract draft ID and full summary
     */
    @InvocableMethod(
        label='Review Deal Discount'
        description='Checks a requested discount on a deal with the MuleSoft Agent Fabric Deal Desk (pricing policy, customer credit, contract draft) and returns Approved, VP Approval Required or Not Allowed.'
        category='Deal Desk'
        callout=true
    )
    public static List<Response> execute(List<Request> requests) {
        OpportunityAccess access = queryOpportunities(requests);
        List<Response> responses = new List<Response>();
        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
        List<Response> responsesToUpdate = new List<Response>();

        for (Request req : requests) {
            Response res = processRequest(req, access);
            responses.add(res);
            if (res.isSuccess && req.opportunityId != null && access.opportunitiesById.containsKey(req.opportunityId)) {
                responsesToUpdate.add(res);
                opportunitiesToUpdate.add(new Opportunity(
                    Id = req.opportunityId,
                    DD_Decision__c = res.decision,
                    DD_Requested_Discount__c = req.discountPercent,
                    DD_Contract_Draft_Id__c = res.contractDraftId,
                    DD_Deal_Desk_Summary__c = res.summary
                ));
            }
        }

        saveDecisions(opportunitiesToUpdate, responsesToUpdate);
        return responses;
    }

    /**
     * Reads the requested Opportunities as the running user. A missing Deal Desk field permission
     * (QueryException in USER_MODE) is turned into a readable error instead of failing the whole action.
     */
    private static OpportunityAccess queryOpportunities(List<Request> requests) {
        OpportunityAccess access = new OpportunityAccess();
        Set<Id> opportunityIds = new Set<Id>();
        for (Request req : requests) {
            if (req.opportunityId != null) {
                opportunityIds.add(req.opportunityId);
            }
        }
        if (opportunityIds.isEmpty()) {
            return access;
        }
        try {
            access.opportunitiesById = new Map<Id, Opportunity>([
                SELECT Id, DD_Deal_ID__c
                FROM Opportunity
                WHERE Id IN :opportunityIds
                WITH USER_MODE
            ]);
        } catch (QueryException e) {
            System.debug(LoggingLevel.WARN, 'Deal Desk Opportunity query blocked for the running user: ' + e.getMessage());
            access.errorMessage = 'You do not have access to the Deal Desk fields on Opportunity. '
                + 'Ask your Salesforce admin to assign the ' + DEAL_DESK_PERMISSION_SET + ' permission set.';
        }
        return access;
    }

    private static Response processRequest(Request req, OpportunityAccess access) {
        Response res = new Response();
        String opportunityProblem = access.problemFor(req.opportunityId);
        String dealId = String.isNotBlank(req.dealId)
            ? req.dealId
            : access.opportunitiesById.get(req.opportunityId)?.DD_Deal_ID__c;
        if (String.isBlank(dealId)) {
            res.isSuccess = false;
            if (opportunityProblem != null) {
                res.errorType = 'OPPORTUNITY_NOT_ACCESSIBLE';
                res.errorMessage = opportunityProblem;
            } else {
                res.errorType = 'MISSING_DEAL_ID';
                res.errorMessage = 'No Deal Desk Deal ID found. Give the deal ID (for example ACME-Q4) or an Opportunity that has one.';
            }
            return res;
        }
        try {
            DD_DealDeskBrokerService.BrokerResult result =
                DD_DealDeskBrokerService.reviewDeal(dealId, req.discountPercent);
            res.isSuccess = result.isSuccess;
            res.decision = result.decision;
            res.contractDraftId = result.contractDraftId;
            res.summary = result.summary;
            res.errorMessage = result.errorMessage;
            res.errorType = result.isSuccess ? null : 'BROKER_TASK_' + result.taskState;
        } catch (DD_DealDeskBrokerService.DealDeskBrokerException e) {
            res.isSuccess = false;
            res.errorMessage = e.getMessage();
            res.errorType = e.getTypeName();
        }
        if (res.isSuccess && opportunityProblem != null) {
            // The decision is still returned; it just cannot be saved on the Opportunity.
            res.errorMessage = 'Decision returned, but it was not saved on the Opportunity: ' + opportunityProblem;
        }
        return res;
    }

    private static void saveDecisions(List<Opportunity> opportunitiesToUpdate, List<Response> matchingResponses) {
        if (opportunitiesToUpdate.isEmpty()) {
            return;
        }
        List<Database.SaveResult> saveResults =
            Database.update(opportunitiesToUpdate, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < saveResults.size(); i++) {
            if (!saveResults[i].isSuccess()) {
                // The broker decision is still returned; only the Opportunity update failed.
                matchingResponses[i].errorMessage = 'Decision returned, but saving it on the Opportunity failed: '
                    + saveResults[i].getErrors()[0].getMessage();
            }
        }
    }

    /**
     * Opportunities the running user can read, or why they could not be read.
     */
    private class OpportunityAccess {
        Map<Id, Opportunity> opportunitiesById = new Map<Id, Opportunity>();
        String errorMessage;

        /**
         * Returns why the given Opportunity cannot be used, or null when it can (or none was given).
         */
        String problemFor(Id opportunityId) {
            if (opportunityId == null || opportunitiesById.containsKey(opportunityId)) {
                return null;
            }
            return errorMessage != null
                ? errorMessage
                : 'Opportunity ' + opportunityId + ' was not found or is not shared with you.';
        }
    }

    /**
     * Input for one Deal Desk review.
     */
    public class Request {
        @InvocableVariable(label='Opportunity Id' description='Opportunity to review. Its Deal Desk Deal ID is used when Deal ID is empty, and the decision is saved on it.' required=false)
        public Id opportunityId;

        @InvocableVariable(label='Deal ID' description='Deal Desk deal ID, for example ACME-Q4. Optional when Opportunity Id is given.' required=false)
        public String dealId;

        @InvocableVariable(label='Discount Percent' description='Requested discount in percent, for example 20 for 20%.' required=true)
        public Decimal discountPercent;
    }

    /**
     * Result of one Deal Desk review.
     */
    public class Response {
        @InvocableVariable(label='Success' description='True when the Deal Desk returned a decision')
        public Boolean isSuccess;

        @InvocableVariable(label='Decision' description='Approved, VP Approval Required, Not Allowed or Needs Info')
        public String decision;

        @InvocableVariable(label='Contract Draft ID' description='Contract draft ID from the Contract Agent, empty when not allowed')
        public String contractDraftId;

        @InvocableVariable(label='Summary' description='Full Deal Desk reply: margin impact, credit report (PAN masked) and contract terms')
        public String summary;

        @InvocableVariable(label='Error Message' description='What went wrong, if the review failed')
        public String errorMessage;

        @InvocableVariable(label='Error Type' description='Error category, if the review failed')
        public String errorType;
    }
}
