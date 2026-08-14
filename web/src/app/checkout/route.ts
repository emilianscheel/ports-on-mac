import { polar } from "@/lib/polar";

export async function GET(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const products = url.searchParams.getAll("products");

    if (products.length === 0) {
        return Response.json(
            { error: "Missing products in query params" },
            { status: 400 },
        );
    }

    try {
        const result = await polar.checkouts.create({ products });
        return Response.redirect(result.url, 302);
    } catch (error) {
        console.error(error);
        return new Response(null, { status: 500 });
    }
}
