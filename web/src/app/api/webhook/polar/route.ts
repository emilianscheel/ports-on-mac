import { validateEvent, WebhookVerificationError } from "@polar-sh/sdk/webhooks";

export async function POST(request: Request): Promise<Response> {
    const body = await request.text();

    let event: ReturnType<typeof validateEvent>;
    try {
        event = validateEvent(
            body,
            {
                "webhook-id": request.headers.get("webhook-id") ?? "",
                "webhook-timestamp": request.headers.get("webhook-timestamp") ?? "",
                "webhook-signature": request.headers.get("webhook-signature") ?? "",
            },
            process.env.POLAR_WEBHOOK_SECRET ?? "",
        );
    } catch (error) {
        if (error instanceof WebhookVerificationError) {
            return Response.json({ received: false }, { status: 403 });
        }
        throw error;
    }

    switch (event.type) {
        case "order.paid":
            // TODO: grant access for the paid order
            break;
        case "customer.state_changed":
            // TODO: sync Polar customer state
            break;
        default:
            break;
    }

    return Response.json({ received: true });
}
