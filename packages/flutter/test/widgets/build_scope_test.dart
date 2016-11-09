// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'test_widgets.dart';

class ProbeWidget extends StatefulWidget {
  @override
  ProbeWidgetState createState() => new ProbeWidgetState();
}

class ProbeWidgetState extends State<ProbeWidget> {
  static int buildCount = 0;

  @override
  void initState() {
    super.initState();
    setState(() {});
  }

  @override
  void didUpdateConfig(ProbeWidget oldConfig) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    setState(() {});
    buildCount++;
    return new Container();
  }
}

class BadWidget extends StatelessWidget {
  BadWidget(this.parentState);

  final BadWidgetParentState parentState;

  @override
  Widget build(BuildContext context) {
    parentState._markNeedsBuild();
    return new Container();
  }
}

class BadWidgetParent extends StatefulWidget {
  @override
  BadWidgetParentState createState() => new BadWidgetParentState();
}

class BadWidgetParentState extends State<BadWidgetParent> {
  void _markNeedsBuild() {
    setState(() {
      // Our state didn't really change, but we're doing something pathological
      // here to trigger an interesting scenario to test.
    });
  }

  @override
  Widget build(BuildContext context) {
    return new BadWidget(this);
  }
}

class BadDisposeWidget extends StatefulWidget {
  @override
  BadDisposeWidgetState createState() => new BadDisposeWidgetState();
}

class BadDisposeWidgetState extends State<BadDisposeWidget> {
  @override
  Widget build(BuildContext context) {
    return new Container();
  }

  @override
  void dispose() {
    setState(() { /* This is invalid behavior. */ });
    super.dispose();
  }
}

class StatefulWrapper extends StatefulWidget {
  StatefulWrapper({
    Key key,
    this.child,
  }) : super(key: key);

  final Widget child;

  @override
  StatefulWrapperState createState() => new StatefulWrapperState();
}

class StatefulWrapperState extends State<StatefulWrapper> {

  void trigger() {
    setState(() { built = null; });
  }

  int built;
  int oldBuilt;

  static int buildId = 0;

  @override
  Widget build(BuildContext context) {
    buildId += 1;
    built = buildId;
    return config.child;
  }
}

class Wrapper extends StatelessWidget {
  Wrapper({
    Key key,
    this.child,
  }) : super(key: key);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

void main() {
  testWidgets('Legal times for setState', (WidgetTester tester) async {
    GlobalKey flipKey = new GlobalKey();
    expect(ProbeWidgetState.buildCount, equals(0));
    await tester.pumpWidget(new ProbeWidget());
    expect(ProbeWidgetState.buildCount, equals(1));
    await tester.pumpWidget(new ProbeWidget());
    expect(ProbeWidgetState.buildCount, equals(2));
    await tester.pumpWidget(new FlipWidget(
      key: flipKey,
      left: new Container(),
      right: new ProbeWidget()
    ));
    expect(ProbeWidgetState.buildCount, equals(2));
    FlipWidgetState flipState1 = flipKey.currentState;
    flipState1.flip();
    await tester.pump();
    expect(ProbeWidgetState.buildCount, equals(3));
    FlipWidgetState flipState2 = flipKey.currentState;
    flipState2.flip();
    await tester.pump();
    expect(ProbeWidgetState.buildCount, equals(3));
    await tester.pumpWidget(new Container());
    expect(ProbeWidgetState.buildCount, equals(3));
  });

  testWidgets('Setting parent state during build is forbidden', (WidgetTester tester) async {
    await tester.pumpWidget(new BadWidgetParent());
    expect(tester.takeException(), isNotNull);
    await tester.pumpWidget(new Container());
  });

  testWidgets('Setting state during dispose is forbidden', (WidgetTester tester) async {
    await tester.pumpWidget(new BadDisposeWidget());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(new Container());
    expect(tester.takeException(), isNotNull);
  });

  testWidgets('Dirty element list sort order', (WidgetTester tester) async {
    GlobalKey key1 = new GlobalKey(debugLabel: 'key1');
    GlobalKey key2 = new GlobalKey(debugLabel: 'key2');

    bool didMiddle = false;
    Widget middle;
    List<StateSetter> setStates = <StateSetter>[];
    Widget builder(BuildContext context, StateSetter setState) {
      setStates.add(setState);
      bool returnMiddle = !didMiddle;
      didMiddle = true;
      return new Wrapper(
        child: new Wrapper(
          child: new StatefulWrapper(
            child: returnMiddle ? middle : new Container(),
          ),
        ),
      );
    }
    Widget part1 = new Wrapper(
      child: new KeyedSubtree(
        key: key1,
        child: new StatefulBuilder(
          builder: builder,
        ),
      ),
    );
    Widget part2 = new Wrapper(
      child: new KeyedSubtree(
        key: key2,
        child: new StatefulBuilder(
          builder: builder,
        ),
      ),
    );

    middle = part2;
    await tester.pumpWidget(part1);

    for (StatefulWrapperState state in tester.stateList/*<StatefulWrapperState>*/(find.byType(StatefulWrapper))) {
      expect(state.built, isNotNull);
      state.oldBuilt = state.built;
      state.trigger();
    }
    for (StateSetter setState in setStates)
      setState(() { });

    StatefulWrapperState.buildId = 0;
    middle = part1;
    didMiddle = false;
    await tester.pumpWidget(part2);

    for (StatefulWrapperState state in tester.stateList/*<StatefulWrapperState>*/(find.byType(StatefulWrapper))) {
      expect(state.built, isNotNull);
      expect(state.built, isNot(equals(state.oldBuilt)));
    }

  });
}