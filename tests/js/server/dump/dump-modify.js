/* jshint strict: false, sub: true */
/* global print, arango, assertEqual, assertTrue, assertFalse */
'use strict';

// /////////////////////////////////////////////////////////////////////////////
// DISCLAIMER
// 
// Copyright 2016-2019 ArangoDB GmbH, Cologne, Germany
// Copyright 2014 triagens GmbH, Cologne, Germany
// 
// Licensed under the Apache License, Version 2.0 (the "License")
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//      http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// 
// Copyright holder is ArangoDB GmbH, Cologne, Germany
// 
// @author Wilfried Goesgens
// //////////////////////////////////////////////////////////////////////////////

var internal = require("internal");
var jsunity = require("jsunity");

////////////////////////////////////////////////////////////////////////////////
/// @brief test suite
////////////////////////////////////////////////////////////////////////////////

function dumpTestSuite () {
  'use strict';
  var db = internal.db;

  return {

////////////////////////////////////////////////////////////////////////////////
/// @brief test the empty collection
////////////////////////////////////////////////////////////////////////////////

    testEmpty : function () {
      var c = db._collection("UnitTestsDumpEmpty");

      c.ensureIndex({type: "hash", fields: ["abc"]});
      assertTrue(true);
    },

////////////////////////////////////////////////////////////////////////////////
/// @brief test the collection with many documents
////////////////////////////////////////////////////////////////////////////////

    testMany : function () {
      var c = db._collection("UnitTestsDumpMany");
      var p = c.properties();

      assertEqual(2, c.type()); // document
      assertFalse(p.waitForSync);
      assertFalse(p.isVolatile);


      assertEqual(1, c.getIndexes().length); // just primary index
      assertEqual("primary", c.getIndexes()[0].type);

      c.ensureIndex({type: "hash", fields: ["abc"]});

      assertEqual(100000, c.count());

      let l = [], results = [];
      for (let i = 0; i < 100000; i += 2) {
        l.push("test" + i);
        if (l.length === 10000) {
          results = results.concat(c.document(l));
          l = [];
        }
      }

      let j = 0;
      for (let i = 0; i < 100000; i += 2) {
        let doc = results[j++];
        assertEqual(i, doc.value1);
        assertEqual("this is a test", doc.value2);
        assertEqual("test" + i, doc.value3);
      }

      // remove half of the documents
      j = 0;
      for (let i = 0; i < 100000; i += 2) {
        let doc = results[j++];
        l.push(doc._key);
        if (l.length === 10000) {
          c.remove(l);
          l = [];
        }
      }

      // add another bunch of documents
      l = [];
      for (let i = 100001; i < 200000; i += 2) {
        l.push({_key: 'test' + i ,
                abc: i,
                value1: i,
                value2: "this is a test", 
                value3: "test" + i
               });
        if (l.length === 10000) {
          c.insert(l);
          l = [];
        }
      }
    },

////////////////////////////////////////////////////////////////////////////////
/// @brief test the edges collection
////////////////////////////////////////////////////////////////////////////////

    testEdges : function () {
      var c = db._collection("UnitTestsDumpEdges");
      var p = c.properties();

      assertEqual(3, c.type()); // edges
      assertFalse(p.waitForSync);
      assertFalse(p.isVolatile);

      assertEqual(2, c.getIndexes().length); // primary index + edges index
      assertEqual("primary", c.getIndexes()[0].type);
      assertEqual("edge", c.getIndexes()[1].type);
      assertEqual(10, c.count());
      c.ensureIndex({type: "hash", fields: ["abc"]});

      // remove half of the documents
      for (let i = 0; i < 10; i+=2) {
        var doc = c.document("test" + i);
        assertEqual(i + "->" + (i + 1), doc.what);
        c.remove(doc._key);
      }
      // add another bunch of documents
      for (let i = 11; i < 20; i+=2) {
        c.save({_key: 'test'+ i,
                abc: i,
                value2: "this is a test", 
                value3: "test" + i,
                _from: "UnitTestsDumpMany/test" + i,
                _to: "UnitTestsDumpMany/test" + (i + 1), 
                what: i + "->" + (i + 1)
               });
      }
    },

////////////////////////////////////////////////////////////////////////////////
/// @brief test the order of documents
////////////////////////////////////////////////////////////////////////////////

    testOrder : function () {
      var c = db._collection("UnitTestsDumpOrder");
      var p = c.properties();

      assertEqual(2, c.type()); // document
      assertFalse(p.waitForSync);
      assertFalse(p.isVolatile);

      assertEqual(1, c.getIndexes().length); // just primary index
      assertEqual("primary", c.getIndexes()[0].type);
      assertEqual(3, c.count());
    },

////////////////////////////////////////////////////////////////////////////////
/// @brief test document removal & update
////////////////////////////////////////////////////////////////////////////////

    testRemoved : function () {
      var c = db._collection("UnitTestsDumpRemoved");
      var p = c.properties();

      assertEqual(2, c.type()); // document
      assertFalse(p.waitForSync);
      assertFalse(p.isVolatile);

      assertEqual(1, c.getIndexes().length); // just primary index
      assertEqual("primary", c.getIndexes()[0].type);
      assertEqual(9000, c.count());

      c.ensureIndex({type: "hash", fields: ["abc"]});
      let docs = [];
      for (let i = 5; i < 10000; i += 10) {
        docs.push("test" + i);
      }
      c.remove(docs);
      c.save({ _key: "test" + 999999, value: 999999 });
    },

////////////////////////////////////////////////////////////////////////////////
/// @brief test indexes
////////////////////////////////////////////////////////////////////////////////

    testIndexes : function () {
      var c = db._collection("UnitTestsDumpIndexes");
      var p = c.properties();

      assertEqual(2, c.type()); // document
      assertFalse(p.waitForSync);
      assertFalse(p.isVolatile);

      assertEqual(9, c.getIndexes().length);
      assertEqual("primary", c.getIndexes()[0].type);

      assertEqual("hash", c.getIndexes()[1].type);
      assertTrue(c.getIndexes()[1].unique);
      assertFalse(c.getIndexes()[1].sparse);
      assertEqual([ "a_uc" ], c.getIndexes()[1].fields);

      assertEqual("skiplist", c.getIndexes()[2].type);
      assertFalse(c.getIndexes()[2].unique);
      assertFalse(c.getIndexes()[2].sparse);
      assertEqual([ "a_s1", "a_s2" ], c.getIndexes()[2].fields);

      assertEqual("hash", c.getIndexes()[3].type);
      assertFalse(c.getIndexes()[3].unique);
      assertFalse(c.getIndexes()[3].sparse);
      assertEqual([ "a_h1", "a_h2" ], c.getIndexes()[3].fields);

      assertEqual("skiplist", c.getIndexes()[4].type);
      assertTrue(c.getIndexes()[4].unique);
      assertFalse(c.getIndexes()[4].sparse);
      assertEqual([ "a_su" ], c.getIndexes()[4].fields);

      assertEqual("hash", c.getIndexes()[5].type);
      assertFalse(c.getIndexes()[5].unique);
      assertTrue(c.getIndexes()[5].sparse);
      assertEqual([ "a_hs1", "a_hs2" ], c.getIndexes()[5].fields);

      assertEqual("skiplist", c.getIndexes()[6].type);
      assertFalse(c.getIndexes()[6].unique);
      assertTrue(c.getIndexes()[6].sparse);
      assertEqual([ "a_ss1", "a_ss2" ], c.getIndexes()[6].fields);

      assertFalse(c.getIndexes()[7].unique);
      assertEqual("fulltext", c.getIndexes()[7].type);
      assertEqual([ "a_f" ], c.getIndexes()[7].fields);

      assertEqual("geo", c.getIndexes()[8].type);
      assertEqual([ "a_la", "a_lo" ], c.getIndexes()[8].fields);
      assertFalse(c.getIndexes()[8].unique);

      assertEqual(0, c.count());
      c.ensureIndex({type: "hash", fields: ["abc"]});
    },

////////////////////////////////////////////////////////////////////////////////
/// @brief test truncate
////////////////////////////////////////////////////////////////////////////////

    testTruncated : function () {
      var c = db._collection("UnitTestsDumpTruncated");
      var p = c.properties();

      assertEqual(2, c.type()); // document
      assertFalse(p.waitForSync);

      assertEqual(1, c.getIndexes().length); // just primary index
      assertEqual("primary", c.getIndexes()[0].type);
      assertEqual(0, c.count());
    },

////////////////////////////////////////////////////////////////////////////////
/// @brief test keygen
////////////////////////////////////////////////////////////////////////////////

    testKeygen : function () {
      if (arango.getRole() === "COORDINATOR") {
        // Only executed on single server tests.
        return;
      }
      var c = db._collection("UnitTestsDumpKeygen");
      var p = c.properties();

      assertEqual(2, c.type()); // document
      assertFalse(p.waitForSync);
      assertFalse(p.isVolatile);
      assertEqual("autoincrement", p.keyOptions.type);
      assertFalse(p.keyOptions.allowUserKeys);
      assertEqual(7, p.keyOptions.offset);
      assertEqual(42, p.keyOptions.increment);

      assertEqual(1, c.getIndexes().length); // just primary index
      assertEqual("primary", c.getIndexes()[0].type);
      assertEqual(1000, c.count());

      for (let i = 0; i < 1000; ++i) {
        var doc = c.document(String(7 + (i * 42)));

        assertEqual(String(7 + (i * 42)), doc._key);
        assertEqual(i, doc.value);
        assertEqual({ value: [ i, i ] }, doc.more);
      }

      for (let i = 0; i < 1000; ++i) {
        c.save({value: i, more: [ i, i ] });
      }
    },

////////////////////////////////////////////////////////////////////////////////
/// @brief test strings
////////////////////////////////////////////////////////////////////////////////

    testStrings : function () { // todo: what to change here?
      var c = db._collection("UnitTestsDumpStrings");
      var p = c.properties();

      assertEqual(2, c.type()); // document
      assertFalse(p.waitForSync);
      assertFalse(p.isVolatile);

      assertEqual(1, c.getIndexes().length); // just primary index
      assertEqual("primary", c.getIndexes()[0].type);
      assertEqual(8, c.count());

      var texts = [
        "big. Really big. He moment. Magrathea! - insisted Arthur, - I do you can sense no further because it doesn't fit properly. In my the denies faith, and the atmosphere beneath You are not cheap He was was his satchel. He throughout Magrathea. - He pushed a tore the ecstatic crowd. Trillian sat down the time, the existence is it? And he said, - What they don't want this airtight hatchway. - it's we you shooting people would represent their Poet Master Grunthos is in his mind.",
        "Ultimo cadere chi sedete uso chiuso voluto ora. Scotendosi portartela meraviglia ore eguagliare incessante allegrezza per. Pensava maestro pungeva un le tornano ah perduta. Fianco bearmi storia soffio prende udi poteva una. Cammino fascino elisire orecchi pollici mio cui sai sul. Chi egli sino sei dita ben. Audace agonie groppa afa vai ultima dentro scossa sii. Alcuni mia blocco cerchi eterno andare pagine poi. Ed migliore di sommesso oh ai angoscia vorresti.",
        "?????? ?????????? ?????? ?????????? ?????? ??????????. ???????????? ?????? ???????????? ???????????? ?????? ?????? ?????? ???????????? ????????????. ?????????????????? ?????? ?????????????????? ?????? ?????? ?????????????????? ??????????????????. ?????? ?????? ?????? ?????? ?????????? ?????????? ??????????. ?????? ?????????????????? ?????????????????? ?????????????????? ?????????????????? ??????. ?????????????????? ?????? rites ?????????????????? ?????????????????? ?????????????????? ?????? ??????.",
        "Mody laty mnie ludu pole rury Bia??opiotrowiczowi. Domy puer szczypi?? jemy pragn???? zacno???? czytaj??c ojca lasy Nowa wewn??trz klasztoru. Chce n??g mego wami. Zamku sta?? nog?? imion ludzi ustaw Bia??opiotrowiczem. Kwiat Niesio??owskiemu nierostrzygniony Staje bra?? Nauka dachu dum?? Zamku Ko??ciuszkowskie zagon. Jakowa?? zapyta?? dwie m??j sama polu uszakach obyczaje M??j. Niesio??owski ksi????kow??j zimny ma??y dotychczasowa Stryj przestraszone Stolnik??wnie wda?? ??miertelnego. Stanis??awa charty kapeluszach mi??ty bratem ka??da brz??kn???? rydwan.",
        "???????????? ???????????? ???????????? ???????????? ????????????. ?????????????? ?????????????? ?????????????? ??????????????. . ???????????????? ???????????????? ???????????????? ???????????????? ???????????????? ????????????????. ?????? ?????? ?????? ?????? ??????. ?????????????????? ?????????????????? ???? ???? ???? ?????????????????? ?????????????????? ???? ???? ??????????????????.",
        "dotyku. V??dech spalin bude polo??en z??plavov?? detek??n?? kabely 1x UPS Newave Conceptpower DPA 5x 40kVA bude ukon??en v samostatn?? strojovn??. Samotn?? servery maj?? pouze lokalita ??st?? nad zdvojenou podlahou budou zakon??en?? GateWay?? HiroLink - Monitoring rozvad????e RTN na jednotliv??ch z??plavov??ch z??n na soustroj?? resp. technologie jsou ozna??eny SA-MKx.y. Jejich v??stupem je zaji??t??n p??estupem dat z jejich provoz. Na dve????ch vylepen?? v??stra??n?? tabulky. Kabel???? z okruh?? z??lohovan??ch obvod?? v R.MON-I. Monitoring EZS, EPS, ... mo??no zajistit funk??nost?? FireWall?? na strukturovanou kabel?????? vedenou v m??rn??ch j??mk??ch zapu??t??n??ch v ka??d??m racku budou zakon??eny v R.MON-NrNN. Monitoring motorgener??tor??: ????d??c?? syst??m bude zakon??ena v modulu",
        "ramien mu zrejme v??bec niekto je u?? presne ??o m??m tendenciu prisp??sobi?? dych jej p????il, ??o chce. Hmm... V??era sa mi pozdava, len do??kali, ale ke????e som na uz boli u jej nezavrela. Hlava jej to ve m??st?? nepotk??, hodn?? mi to t?? vedci pri hre, ke?? je tu pre Designiu. Pokia?? viete o odbornej??ie texty. Prv??m z tmav??ch uli??iek, ka??d?? to niekedy, zrovn??va?? krok s obrovsk??m batohom na okraj vane a temn?? ??mysly, tak rozm??????am, ak?? som si hromady mailov, ??o chcem a neraz sa pok????al o filmov??m klubu v bud??cnosti rozhodne unies?? mlad?? maliarku (Linda Rybov??), ktor?? so",
        " ????????????. ????????????. ???????????? ????????????. ????????????. ????????????. ????????????. ????????? ????????? ????????? ????????? ?????????. ???????????? ????????????. ???????????? ????????????. ???????????? ???????????? ???????????? ???????????? ???????????? ????????????. ???????????? . ???????????? ???????????? ???????????? ???????????? ???????????? ?????????. ???????????? ????????? ???????????? ???????????? ???????????? ????????????. ???????????? ???????????? ???????????? ???????????? ?????????. ????????????."
      ];

      texts.forEach(function (t, i) {
        var doc = c.document("text" + i);

        assertEqual(t, doc.value);
      });

    },

////////////////////////////////////////////////////////////////////////////////
/// @brief test committed trx
////////////////////////////////////////////////////////////////////////////////

    testTransactionCommit : function () { // todo
      if (arango.getRole() === "COORDINATOR") {
        // Only executed on single server tests.
        return;
      }
      var c = db._collection("UnitTestsDumpTransactionCommit");

      assertEqual(1000, c.count());

      for (var i = 0; i < 1000; ++i) {
        var doc = c.document("test" + i);

        assertEqual(i, doc.value1);
        assertEqual("this is a test", doc.value2);
        assertEqual("test" + i, doc.value3);
      }
    },

////////////////////////////////////////////////////////////////////////////////
/// @brief test committed trx
////////////////////////////////////////////////////////////////////////////////

    testTransactionUpdate : function () {
      if (arango.getRole() === "COORDINATOR") {
        // Only executed on single server tests.
        return;
      }
      var c = db._collection("UnitTestsDumpTransactionUpdate");

      assertEqual(1000, c.count());

      for (var i = 0; i < 1000; ++i) {
        var doc = c.document("test" + i);

        assertEqual(i, doc.value1);
        assertEqual("this is a test", doc.value2);
        if (i % 2 === 0) {
          assertEqual(i, doc.value3);
        }
        else {
          assertEqual("test" + i, doc.value3);
        }
      }
    },

////////////////////////////////////////////////////////////////////////////////
/// @brief test aborted trx
////////////////////////////////////////////////////////////////////////////////

    testTransactionAbort : function () { // todo
      if (arango.getRole() === "COORDINATOR") {
        // Only executed on single server tests.
        return;
      }
      var c = db._collection("UnitTestsDumpTransactionAbort");

      assertEqual(1, c.count());

      assertTrue(c.exists("foo"));
    },

////////////////////////////////////////////////////////////////////////////////
/// @brief test persistent
////////////////////////////////////////////////////////////////////////////////

    testPersistent : function () { // todo: does it make sense at all?
      if (arango.getRole() === "COORDINATOR") {
        // Only executed on single server tests.
        return;
      }
      var c = db._collection("UnitTestsDumpPersistent");
      var p = c.properties();

      assertEqual(2, c.getIndexes().length);
      assertEqual("primary", c.getIndexes()[0].type);
      assertEqual("persistent", c.getIndexes()[1].type);
      assertEqual(10000, c.count());

      var res = db._query("FOR doc IN " + c.name() + " FILTER doc.value >= 0 RETURN doc").toArray();
      assertEqual(10000, res.length);

      res = db._query("FOR doc IN " + c.name() + " FILTER doc.value >= 5000 RETURN doc").toArray();
      assertEqual(5000, res.length);

      res = db._query("FOR doc IN " + c.name() + " FILTER doc.value >= 9000 RETURN doc").toArray();
      assertEqual(1000, res.length);

      res = db._query("FOR doc IN " + c.name() + " FILTER doc.value >= 10000 RETURN doc").toArray();
      assertEqual(0, res.length);
    },

////////////////////////////////////////////////////////////////////////////////
/// @brief test view restoring
////////////////////////////////////////////////////////////////////////////////
/* not yet implemented
    testView : function () {
      try {
        db._createView("check", "arangosearch", {});
      } catch (err) {}

      let views = db._views();
      if (views.length === 0) {
        return; // arangosearch views are not supported
      }

      let view = db._view("UnitTestsDumpView");
      assertTrue(view !== null);
      let props = view.properties();
      assertEqual(Object.keys(props.links).length, 1);
      assertTrue(props.hasOwnProperty("links"));
      assertTrue(props.links.hasOwnProperty("UnitTestsDumpViewCollection"));
      assertTrue(props.links.UnitTestsDumpViewCollection.hasOwnProperty("includeAllFields"));
      assertTrue(props.links.UnitTestsDumpViewCollection.hasOwnProperty("fields"));
      assertTrue(props.links.UnitTestsDumpViewCollection.includeAllFields);

      assertEqual(props.consolidationIntervalMsec, 0);
      assertEqual(props.cleanupIntervalStep, 456);
      assertTrue(Math.abs(props.consolidationPolicy.threshold - 0.3) < 0.001);
      assertEqual(props.consolidationPolicy.type, "bytes_accum");

      var res = db._query("FOR doc IN " + view.name() + " SEARCH doc.value >= 0 OPTIONS { waitForSync: true } RETURN doc").toArray();
      assertEqual(5000, res.length);

      res = db._query("FOR doc IN " + view.name() + " SEARCH doc.value >= 2500 RETURN doc").toArray();
      assertEqual(2500, res.length);

      res = db._query("FOR doc IN " + view.name() + " SEARCH doc.value >= 5000 RETURN doc").toArray();
      assertEqual(0, res.length);

      res = db._query("FOR doc IN UnitTestsDumpView SEARCH PHRASE(doc.text, 'foxx jumps over', 'text_en')  RETURN doc").toArray();
      assertEqual(1, res.length);
    }
*/
  };
}

////////////////////////////////////////////////////////////////////////////////
/// @brief executes the test suite
////////////////////////////////////////////////////////////////////////////////

jsunity.run(dumpTestSuite);

return jsunity.done();
