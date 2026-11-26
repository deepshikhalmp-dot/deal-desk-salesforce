/**
 * @description HttpCalloutMock for the Agent Fabric Deal Desk broker (A2A v1.0 JSON-RPC replies).
 */
@isTest
public class DD_DealDeskBrokerMock implements HttpCalloutMock {

    public static final String APPROVED_TEXT =
        'DEAL DESK DECISION: APPROVED (ACME-Q4, 10% discount) | Margin 27.8% | Contract draft: CTR-ACME-Q4-10 | Credit report: Customer PAN: AAACA****F.';
    public static final String VP_TEXT =
        'DEAL DESK DECISION: VP APPROVAL REQUIRED (ACME-Q4, 20% discount) | Margin 18.8% | Contract draft (pending VP approval): CTR-ACME-Q4-20 | Credit report: Customer PAN: AAACA****F.';
    public static final String NOT_ALLOWED_TEXT =
        'DEAL DESK DECISION: NOT ALLOWED (GLOBEX-Q4, 30% discount) | Margin -11.4% | No contract drafted. Please revise the discount to 25% or less.';
    public static final String NEED_INFO_TEXT =
        'Please share the deal ID (for example ACME-Q4) and the discount %.';

    public static HttpRequest lastRequest;

    private final Integer statusCode;
    private final String body;

    public DD_DealDeskBrokerMock(Integer statusCode, String body) {
        this.statusCode = statusCode;
        this.body = body;
    }

    /**
     * @description Builds a broker reply with the given task state and text.
     */
    public static DD_DealDeskBrokerMock reply(String state, String text) {
        Map<String, Object> status = new Map<String, Object>{
            'state' => state,
            'message' => new Map<String, Object>{
                'role' => 'ROLE_AGENT',
                'parts' => new List<Object>{ new Map<String, Object>{ 'text' => text } }
            }
        };
        Map<String, Object> root = new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id' => '1',
            'result' => new Map<String, Object>{ 'task' => new Map<String, Object>{ 'status' => status } }
        };
        return new DD_DealDeskBrokerMock(200, JSON.serialize(root));
    }

    public HttpResponse respond(HttpRequest request) {
        lastRequest = request;
        HttpResponse response = new HttpResponse();
        response.setStatusCode(statusCode);
        response.setHeader('Content-Type', 'application/json');
        response.setBody(body);
        return response;
    }
}
