/**
 * @description Test data for the Deal Desk demo classes.
 */
@isTest
public class DD_TestDataFactory {

    public static final String ACME_DEAL_ID = 'ACME-Q4';
    public static final String DEAL_DESK_PERMSET = 'DD_Deal_Desk_User';
    private static final String DEAL_DESK_USER_PREFIX = 'dd.dealdesk.user.';
    private static final String NO_ACCESS_USER_PREFIX = 'dd.noaccess.user.';

    /**
     * @description Creates a Standard User with the DD_Deal_Desk_User permission set, so tests can
     * run USER_MODE code the way a real Deal Desk user would. The setup DML runs inside System.runAs
     * so callers can insert Accounts/Opportunities in the same transaction without MIXED_DML_OPERATION.
     * @return The inserted User
     */
    public static User createDealDeskUser() {
        User dealDeskUser = buildStandardUser(DEAL_DESK_USER_PREFIX, 'ddtest');
        PermissionSet dealDeskPermSet = [SELECT Id FROM PermissionSet WHERE Name = :DEAL_DESK_PERMSET LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert dealDeskUser;
            insert new PermissionSetAssignment(AssigneeId = dealDeskUser.Id, PermissionSetId = dealDeskPermSet.Id);
        }
        return dealDeskUser;
    }

    /**
     * @description Creates a Standard User without the DD_Deal_Desk_User permission set, for
     * testing what the Deal Desk action does when the user cannot see the Deal Desk fields.
     * @return The inserted User
     */
    public static User createUserWithoutDealDeskAccess() {
        User noAccessUser = buildStandardUser(NO_ACCESS_USER_PREFIX, 'ddnoacc');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert noAccessUser;
        }
        return noAccessUser;
    }

    /**
     * @description Returns the Deal Desk test user created by createDealDeskUser().
     * @return The User
     */
    public static User getDealDeskUser() {
        return getUserByPrefix(DEAL_DESK_USER_PREFIX);
    }

    /**
     * @description Returns the test user created by createUserWithoutDealDeskAccess().
     * @return The User
     */
    public static User getUserWithoutDealDeskAccess() {
        return getUserByPrefix(NO_ACCESS_USER_PREFIX);
    }

    private static String testUsername(String prefix) {
        return prefix + UserInfo.getOrganizationId() + '@example.com';
    }

    private static User getUserByPrefix(String prefix) {
        return [SELECT Id FROM User WHERE Username = :testUsername(prefix) LIMIT 1];
    }

    private static User buildStandardUser(String usernamePrefix, String alias) {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            ProfileId = standardProfile.Id,
            FirstName = 'Deal Desk',
            LastName = 'Tester ' + alias,
            Alias = alias,
            Email = alias + '@example.com',
            Username = testUsername(usernamePrefix),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    /**
     * @description Creates Deal Desk test Opportunities (one Account each) with a Deal Desk Deal ID.
     * @param count Number of Opportunities
     * @param doInsert Insert the records when true
     * @return The Opportunities
     */
    public static List<Opportunity> createDealDeskOpportunities(Integer count, Boolean doInsert) {
        return createDealDeskOpportunities(count, doInsert, null);
    }

    /**
     * @description Creates Deal Desk test Opportunities owned by the given user.
     * @param count Number of Opportunities
     * @param doInsert Insert the records when true
     * @param ownerId Owner of the Accounts and Opportunities (current user when null)
     * @return The Opportunities
     */
    public static List<Opportunity> createDealDeskOpportunities(Integer count, Boolean doInsert, Id ownerId) {
        Id recordOwnerId = ownerId != null ? ownerId : UserInfo.getUserId();
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(Name = 'DD Test Account ' + i, OwnerId = recordOwnerId));
        }
        if (doInsert) {
            insert accounts;
        }
        String openStage = [
            SELECT ApiName FROM OpportunityStage
            WHERE IsActive = true AND IsClosed = false
            ORDER BY SortOrder LIMIT 1
        ].ApiName;
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < count; i++) {
            opportunities.add(new Opportunity(
                Name = 'DD Test Opportunity ' + i,
                AccountId = accounts[i].Id,
                OwnerId = recordOwnerId,
                StageName = openStage,
                CloseDate = Date.today().addDays(30),
                Amount = 5000000,
                DD_Deal_ID__c = ACME_DEAL_ID
            ));
        }
        if (doInsert) {
            insert opportunities;
        }
        return opportunities;
    }
}
