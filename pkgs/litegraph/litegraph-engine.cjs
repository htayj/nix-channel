#!/usr/bin/env node
'use strict';

// External consumer of the two real bundles; needs only Node's standard library.
// Public CLI: node litegraph-engine.cjs ROOT [EVIDENCE-DIR]
// Each bundle is loaded in its own process, without browser/global substitutes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const bundles = {
  source: 'build/litegraph.js',
  minified: 'build/litegraph.min.js',
};

function consume(root, variant, evidenceDirectory) {
  const bundle = path.join(root, bundles[variant]);
  const engine = require(bundle);
  assert.equal(typeof engine, 'object', `${bundle}: CommonJS exports`);
  const { LiteGraph, LGraph } = engine;
  assert.equal(typeof LiteGraph, 'object', 'exports.LiteGraph');
  assert.equal(typeof LGraph, 'function', 'exports.LGraph');
  assert.equal(LGraph, LiteGraph.LGraph, 'exported graph constructor identity');
  assert.equal(engine.LGraphNode, LiteGraph.LGraphNode, 'exported node API identity');
  assert.equal(typeof engine.LGraphNode, 'function', 'exports.LGraphNode');
  assert.equal(typeof LiteGraph.createNode, 'function', 'LiteGraph.createNode');
  // Pinned source assigns exports.LLink from this.LLink, but installs the actual
  // constructor only on LiteGraph.LLink. Do not invent a top-level export shim.
  assert.equal(typeof LiteGraph.LLink, 'function', 'LiteGraph.LLink');

  const graph = new LGraph();
  const nodes = {
    a: LiteGraph.createNode('basic/const', 'A'),
    b: LiteGraph.createNode('basic/const', 'B'),
    operation: LiteGraph.createNode('math/operation', 'Addition'),
    watch: LiteGraph.createNode('basic/watch', 'Result'),
  };
  for (const [name, node] of Object.entries(nodes)) {
    assert.ok(node, `${name}: registered built-in node`);
    assert.equal(node.constructor, LiteGraph.registered_node_types[node.type],
      `${name}: genuine built-in constructor`);
    graph.add(node);
  }
  nodes.a.setProperty('value', 7);
  nodes.b.setProperty('value', 5);
  nodes.operation.setProperty('OP', '+');

  // connect(outputSlot, targetNode, inputSlot) returns the real LLink, not an ID.
  const connections = [
    nodes.a.connect(0, nodes.operation, 0),
    nodes.b.connect(0, nodes.operation, 1),
    nodes.operation.connect(0, nodes.watch, 0),
  ];
  for (const link of connections) {
    assert.ok(link instanceof LiteGraph.LLink, 'connect returns a genuine LLink');
    assert.ok(Number.isInteger(link.id) && link.id > 0, 'allocated link ID');
    assert.equal(graph.links[link.id], link, 'graph owns returned link');
  }
  assert.equal(new Set(connections.map(link => link.id)).size, 3,
    'three distinct link IDs');
  const nodeIds = Object.fromEntries(
    Object.entries(nodes).map(([name, node]) => [name, node.id]));
  assert.equal(new Set(Object.values(nodeIds)).size, 4, 'four distinct node IDs');
  const edges = [
    [connections[0].id, nodes.a.id, 0, nodes.operation.id, 0, 'number,array,object'],
    [connections[1].id, nodes.b.id, 0, nodes.operation.id, 1, 'number'],
    [connections[2].id, nodes.operation.id, 0, nodes.watch.id, 0, 'number'],
  ];

  function assertTopology(current, currentNodes) {
    assert.deepEqual(Object.keys(current.links).map(Number).sort((a, b) => a - b),
      edges.map(edge => edge[0]).sort((a, b) => a - b), 'exact graph edge IDs');
    for (const [name, node] of Object.entries(currentNodes)) {
      assert.ok(node, `${name}: node survives import`);
      assert.equal(node.id, nodeIds[name], `${name}: stable node ID`);
      assert.equal(node.type, nodes[name].type, `${name}: stable built-in type`);
      assert.equal(node.title, nodes[name].title, `${name}: stable title`);
      assert.equal(node.constructor, nodes[name].constructor,
        `${name}: import restores built-in implementation`);
      assert.ok(!node.has_errors, `${name}: no configure replacement node`);
      assert.equal(node.graph, current, `${name}: belongs to current graph`);
      assert.equal(current.getNodeById(node.id), node, `${name}: ID lookup`);
    }
    for (const edge of edges) {
      const [id, originId, originSlot, targetId, targetSlot] = edge;
      const link = current.links[id];
      assert.ok(link instanceof LiteGraph.LLink, `${id}: genuine graph link`);
      assert.deepEqual(link.serialize(), edge, `${id}: ID, endpoints, slots and type`);
      const origin = current.getNodeById(originId);
      const target = current.getNodeById(targetId);
      assert.deepEqual(origin.outputs[originSlot].links, [id],
        `${id}: source output owns link ID`);
      assert.equal(target.inputs[targetSlot].link, id,
        `${id}: destination input owns link ID`);
    }
  }

  function execute(current, currentNodes, aValue, expected) {
    assertTopology(current, currentNodes);
    // runStep(iterations, do_not_catch_errors, optional_limit): let any upstream
    // exception fail the consumer instead of being swallowed by the engine.
    current.runStep(1, true);
    const result = {
      a: currentNodes.a.getOutputData(0),
      b: currentNodes.b.getOutputData(0),
      math: currentNodes.operation.getOutputData(0),
      watchInput: currentNodes.watch.getInputData(0),
      watch: currentNodes.watch.value,
      links: edges.map(edge => ({ id: edge[0], data: current.links[edge[0]].data })),
    };
    assert.equal(result.a, aValue, 'constant A numeric output');
    assert.equal(result.b, 5, 'constant B numeric output');
    assert.equal(result.math, expected, 'math/operation exact numeric output');
    assert.equal(result.watchInput, expected, 'value travels to watch input');
    assert.equal(result.watch, expected, 'basic/watch exact numeric value');
    assert.deepEqual(result.links.map(link => link.data), [aValue, 5, expected],
      'live data travels through all three genuine links');
    return result;
  }

  function serialize(current) {
    // Node.serialize clears transient output data and configure mutates its
    // argument's link array. Capture detached JSON, not shared engine objects.
    const data = JSON.parse(JSON.stringify(current.serialize()));
    assert.deepEqual(data.nodes.map(node => node.id).sort((a, b) => a - b),
      Object.values(nodeIds).sort((a, b) => a - b), 'exact serialized node IDs');
    assert.deepEqual(data.links.slice().sort((a, b) => a[0] - b[0]),
      edges.slice().sort((a, b) => a[0] - b[0]), 'exact serialized edges');
    return data;
  }

  const constructedResult = execute(graph, nodes, 7, 12);
  const constructedGraph = serialize(graph);
  const imported = new LGraph();
  // configure(data, keep_old) consumes a parsed JSON object despite the source
  // doc-comment calling the argument a string; false means no missing types.
  assert.equal(imported.configure(JSON.parse(JSON.stringify(constructedGraph))), false,
    'fresh graph configures every serialized built-in successfully');
  const importedNodes = Object.fromEntries(Object.entries(nodeIds)
    .map(([name, id]) => [name, imported.getNodeById(id)]));
  for (const name of Object.keys(nodes)) {
    assert.notEqual(importedNodes[name], nodes[name], `${name}: freshly imported node`);
  }
  const importedResult = execute(imported, importedNodes, 7, 12);
  const importedGraph = serialize(imported);
  // Compare semantic identities and properties, not transient execution state.
  const nodeState = data => data.nodes.map(node => ({
    id: node.id, type: node.type, title: node.title, properties: node.properties,
  })).sort((a, b) => a.id - b.id);
  assert.deepEqual(nodeState(importedGraph), nodeState(constructedGraph),
    'roundtrip preserves all node identities, types, titles and properties');

  importedNodes.a.setProperty('value', 11);
  assert.equal(importedNodes.a.properties.value, 11, 'imported A changes to 11');
  assert.equal(nodes.a.properties.value, 7, 'original A remains independent');
  const mutatedResult = execute(imported, importedNodes, 11, 16);
  const mutatedGraph = serialize(imported);
  assert.equal(mutatedGraph.nodes.find(node => node.id === nodeIds.a).properties.value,
    11, 'live imported mutation serializes');

  const report = {
    bundle,
    variant,
    exportTypes: Object.fromEntries(Object.keys(engine).sort()
      .map(key => [key, typeof engine[key]])),
    nodeIds,
    edges,
    constructed: { result: constructedResult, serialization: constructedGraph },
    imported: { result: importedResult, serialization: importedGraph },
    mutated: { result: mutatedResult, serialization: mutatedGraph },
  };
  if (evidenceDirectory) {
    fs.mkdirSync(evidenceDirectory, { recursive: true });
    fs.writeFileSync(path.join(evidenceDirectory, `engine-${variant}.json`),
      `${JSON.stringify(report, null, 2)}\n`);
  }
  console.log(`${variant}: 7 + 5 = 12; JSON roundtrip = 12; imported 11 + 5 = 16; ` +
    '4 built-in nodes and 3 genuine links preserved');
}

function main(args) {
  if (args[0] === '--bundle') {
    if ((args.length !== 3 && args.length !== 4) ||
        !Object.hasOwn(bundles, args[2])) {
      throw new Error('Internal usage: --bundle ROOT source|minified [EVIDENCE-DIR]');
    }
    consume(path.resolve(args[1]), args[2], args[3] && path.resolve(args[3]));
    return;
  }
  if (args.length !== 1 && args.length !== 2) {
    throw new Error('Usage: node litegraph-engine.cjs ROOT [EVIDENCE-DIR]');
  }
  const root = path.resolve(args[0]);
  const evidenceDirectory = args[1] && path.resolve(args[1]);
  for (const variant of Object.keys(bundles)) {
    const childArgs = [__filename, '--bundle', root, variant];
    if (evidenceDirectory) childArgs.push(evidenceDirectory);
    const child = spawnSync(process.execPath, childArgs, { stdio: 'inherit' });
    if (child.error) throw child.error;
    assert.equal(child.signal, null, `${variant}: child terminated by signal`);
    assert.equal(child.status, 0, `${variant}: engine consumer failed`);
  }
}

main(process.argv.slice(2));
