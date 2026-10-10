static void CheckReasoning(NSURL* root) {
    SPDFMacAIChatStore* store=[[SPDFMacAIChatStore alloc] initWithDirectory:root];
    FakeTransport* transport=[FakeTransport new];FakeTools* tools=[FakeTools new];
    SPDFMacAIChatSession* session=[[SPDFMacAIChatSession alloc] initWithTransport:transport tools:tools definitions:@[] store:store];
    [session send:@"Read the drawing" model:@"fake/reasoning" apiKey:@"test"];
    NSString* prompt=transport.messages.firstObject[@"content"];
    CHECK([prompt containsString:@"Answer the quantity and scope the user asked for"] &&
          [prompt containsString:@"Use the first readable capture to answer."] &&
          [prompt containsString:@"both endpoints"] && [prompt containsString:@"title-block/general notes"],
          "request prompt requires scoped visual evidence, bounded captures and general tolerance checks");
    CHECK(![prompt containsString:@"3.1 mm"] && ![prompt containsString:@"MSK13"],
          "general evidence rules do not hardcode a document or expected answer");
    NSArray* details=@[@{@"type":@"reasoning.encrypted",@"data":@"opaque-fixture-state",@"format":@"fixture"}];
    transport.reply(@{@"content":@"",@"reasoning_details":details,@"tool_calls":@[
        @{@"id":@"drawing",@"function":@{@"name":@"render_page",@"arguments":@"{}"}}]},nil);
    tools.reply(@{@"rendered":@YES});
    CHECK([transport.messages[2][@"reasoning_details"] isEqual:details],"tool continuation preserves opaque model reasoning unchanged");
    CHECK(!session.chat[@"messages"][1][@"reasoning_details"],"reasoning stays request-only, outside displayed/saved history");
    [session cancel];[session send:@"Next question" model:@"fake/other" apiKey:@"test"];
    BOOL retained=NO;for(NSDictionary* message in transport.messages)if(message[@"reasoning_details"])retained=YES;
    CHECK(!retained,"reasoning is not replayed to a different model or new user turn");[session cancel];
}
