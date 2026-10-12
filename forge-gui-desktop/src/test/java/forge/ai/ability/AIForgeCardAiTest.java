package forge.ai.ability;

import java.util.HashMap;
import java.util.Map;

import org.testng.AssertJUnit;
import org.testng.annotations.Test;

import forge.ai.AITest;
import forge.ai.AiAbilityDecision;
import forge.ai.ComputerUtil;
import forge.ai.SpecialCardAi;
import forge.ai.SpellApiToAi;
import forge.game.Game;
import forge.game.ability.ApiType;
import forge.game.card.Card;
import forge.game.card.CardCollection;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.model.FModel;

/** AI play of AIForge cube cards: Double Stroke, Entomb, Skullclamp, Broadside Bombardiers. */
public class AIForgeCardAiTest extends AITest {

    // ---------------- Double Stroke ----------------

    private Card createConspiracy(String name, Player p) {
        // conspiracies live in the variant card DB, not the common one AITest.createCard uses
        return Card.fromPaperCard(FModel.getMagicDb().getVariantCards().getCard(name), p);
    }

    private String doubleStrokeName(Player ai) {
        Card doubleStroke = createConspiracy("Double Stroke", ai);
        SpellAbility sa = new SpellAbility.EmptySa(doubleStroke);
        sa.putParam("AILogic", doubleStroke.getSVar("AgendaLogic"));
        return ai.getController().chooseCardName(sa, x -> true, "Card", "Name a card");
    }

    @Test
    public void testDoubleStrokeNamesHighestRankedNonCounterSpellInDeck() {
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        addCardToZone("Flame Slash", ai, ZoneType.Library);
        addCardToZone("Time Walk", ai, ZoneType.Library);
        addCardToZone("Counterspell", ai, ZoneType.Library);
        addCardToZone("Grizzly Bears", ai, ZoneType.Library);
        Map<String, Double> ranks = new HashMap<>();
        ranks.put("Counterspell", 0.01); // best ranked, but a counterspell
        ranks.put("Time Walk", 0.02);
        ranks.put("Flame Slash", 0.30);
        game.getRules().setCubeDraftRankings(ranks);

        AssertJUnit.assertEquals("Time Walk", doubleStrokeName(ai));
    }

    @Test
    public void testDoubleStrokeNamesNothingWithoutInstantsOrSorceries() {
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        addCardToZone("Grizzly Bears", ai, ZoneType.Library);
        addCardToZone("Counterspell", ai, ZoneType.Library);

        // blank name = the conspiracy is left out of the game (no "Morphling")
        AssertJUnit.assertEquals("", doubleStrokeName(ai));
    }

    @Test
    public void testDoubleStrokeCopyTriggerIsAccepted() {
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        Card doubleStroke = createConspiracy("Double Stroke", ai);
        SpellAbility copy = doubleStroke.getTriggers().iterator().next().ensureAbility();
        copy.setActivatingPlayer(ai);
        AssertJUnit.assertTrue("AI should take the optional copy",
                SpellApiToAi.Converter.get(ApiType.CopySpellAbility).doTriggerNoCostWithSubs(ai, copy, false).willingToPlay());
    }

    // ---------------- Entomb ----------------

    private Card entombChoice(Player ai, CardCollection library) {
        Card entomb = addCardToZone("Entomb", ai, ZoneType.Hand);
        SpellAbility sa = entomb.getFirstSpellAbility();
        sa.setActivatingPlayer(ai);
        return ChangeZoneAi.chooseCardToHiddenOriginChangeZone(ZoneType.Graveyard,
                java.util.List.of(ZoneType.Library), sa, library, ai, ai);
    }

    @Test
    public void testEntombNeverPicksBlightsteel() {
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        CardCollection library = new CardCollection();
        library.add(addCardToZone("Blightsteel Colossus", ai, ZoneType.Library));
        library.add(addCardToZone("Archon of Cruelty", ai, ZoneType.Library));
        addCards("Swamp", 4, ai);
        addCardToZone("Necromancy", ai, ZoneType.Hand); // even with instant reanimation: no window

        AssertJUnit.assertEquals("Archon of Cruelty", entombChoice(ai, library).getName());
    }

    @Test
    public void testEntombSkipsWorldspineWithoutInstantReanimation() {
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        CardCollection library = new CardCollection();
        library.add(addCardToZone("Worldspine Wurm", ai, ZoneType.Library));
        library.add(addCardToZone("Archon of Cruelty", ai, ZoneType.Library));
        addCardToZone("Reanimate", ai, ZoneType.Hand); // sorcery: can't respond to the shuffle trigger

        AssertJUnit.assertEquals("Archon of Cruelty", entombChoice(ai, library).getName());
    }

    @Test
    public void testEntombPicksWorldspineWithAffordableNecromancy() {
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        CardCollection library = new CardCollection();
        library.add(addCardToZone("Worldspine Wurm", ai, ZoneType.Library));
        library.add(addCardToZone("Archon of Cruelty", ai, ZoneType.Library));
        addCards("Swamp", 3, ai);
        addCardToZone("Necromancy", ai, ZoneType.Hand);

        AssertJUnit.assertEquals("Worldspine Wurm", entombChoice(ai, library).getName());
    }

    @Test
    public void testEntombPicksWorldspineWithShallowGraveBeforeCombat() {
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        CardCollection library = new CardCollection();
        library.add(addCardToZone("Worldspine Wurm", ai, ZoneType.Library));
        library.add(addCardToZone("Archon of Cruelty", ai, ZoneType.Library));
        addCards("Swamp", 2, ai);
        addCardToZone("Shallow Grave", ai, ZoneType.Hand);
        game.getPhaseHandler().devModeSet(PhaseType.MAIN1, ai);

        AssertJUnit.assertEquals("Worldspine Wurm", entombChoice(ai, library).getName());
    }

    @Test
    public void testEntombPicksWorldspineWithShallowGraveInOpponentsEndStep() {
        // cast in the opponent's end step, the "exile at the next end step" waits for OUR end step
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        CardCollection library = new CardCollection();
        library.add(addCardToZone("Worldspine Wurm", ai, ZoneType.Library));
        library.add(addCardToZone("Archon of Cruelty", ai, ZoneType.Library));
        addCards("Swamp", 2, ai);
        addCardToZone("Shallow Grave", ai, ZoneType.Hand);
        game.getPhaseHandler().devModeSet(PhaseType.END_OF_TURN, game.getPlayers().get(0));

        AssertJUnit.assertEquals("Worldspine Wurm", entombChoice(ai, library).getName());
    }

    @Test
    public void testEntombSkipsWorldspineWithShallowGraveInOpponentsMainPhase() {
        // Shallow Grave/Corpse Dance exile the creature at end of turn: here it would never attack
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        CardCollection library = new CardCollection();
        library.add(addCardToZone("Worldspine Wurm", ai, ZoneType.Library));
        library.add(addCardToZone("Archon of Cruelty", ai, ZoneType.Library));
        addCards("Swamp", 2, ai);
        addCardToZone("Shallow Grave", ai, ZoneType.Hand);
        game.getPhaseHandler().devModeSet(PhaseType.MAIN2, game.getPlayers().get(0));

        AssertJUnit.assertEquals("Archon of Cruelty", entombChoice(ai, library).getName());
    }

    /** Puts Worldspine Wurm's shuffle trigger on the stack (as if Entomb just resolved); returns the AI's response. */
    private String respondToWorldspineTrigger(String reanimator, int swamps, PhaseType phase, boolean aiTurn) {
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        addCards("Swamp", swamps, ai);
        addCardToZone(reanimator, ai, ZoneType.Hand);
        Card wurm = addCardToZone("Worldspine Wurm", ai, ZoneType.Library);
        game.getPhaseHandler().devModeSet(phase, aiTurn ? ai : game.getPlayers().get(0));

        game.getAction().moveToGraveyard(wurm, null);
        game.getTriggerHandler().runWaitingTriggers();
        game.getStack().addAllTriggeredAbilitiesToStack();
        AssertJUnit.assertFalse("shuffle trigger should be on the stack", game.getStack().isEmpty());

        java.util.List<SpellAbility> chosen = ((forge.ai.PlayerControllerAi) ai.getController()).getAi().chooseSpellAbilityToPlay();
        return chosen == null || chosen.isEmpty() ? null : chosen.get(0).getHostCard().getName();
    }

    @Test
    public void testNecromancyRespondsToWorldspineShuffleTrigger() {
        AssertJUnit.assertEquals("Necromancy", respondToWorldspineTrigger("Necromancy", 3, PhaseType.MAIN1, true));
    }

    @Test
    public void testShallowGraveRespondsToWorldspineShuffleTriggerBeforeCombat() {
        AssertJUnit.assertEquals("Shallow Grave", respondToWorldspineTrigger("Shallow Grave", 2, PhaseType.MAIN1, true));
    }

    @Test
    public void testCorpseDanceRespondsToWorldspineShuffleTriggerBeforeCombat() {
        AssertJUnit.assertEquals("Corpse Dance", respondToWorldspineTrigger("Corpse Dance", 3, PhaseType.MAIN1, true));
    }

    @Test
    public void testShallowGraveRespondsToWorldspineShuffleTriggerInOpponentsEndStep() {
        AssertJUnit.assertEquals("Shallow Grave", respondToWorldspineTrigger("Shallow Grave", 2, PhaseType.END_OF_TURN, false));
    }

    @Test
    public void testShallowGraveDoesNotWasteWorldspineInOpponentsMainPhase() {
        AssertJUnit.assertNull(respondToWorldspineTrigger("Shallow Grave", 2, PhaseType.MAIN2, false));
    }

    @Test
    public void testCorpseDanceDoesNotWasteWorldspineAfterOwnCombat() {
        AssertJUnit.assertNull(respondToWorldspineTrigger("Corpse Dance", 3, PhaseType.MAIN2, true));
    }

    // ---------------- Skullclamp ----------------

    @Test
    public void testSkullclampEquipsTokenItKills() {
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        Card clamp = addCard("Skullclamp", ai);
        Card token = addToken("w_1_1_citizen", ai);
        addCard("Serra Angel", ai);
        addCards("Plains", 2, ai);
        game.getPhaseHandler().devModeSet(PhaseType.MAIN2, ai);
        game.getAction().checkStateEffects(true);

        SpellAbility equip = findSAWithPrefix(clamp, "Equip");
        equip.setActivatingPlayer(ai);
        AiAbilityDecision d = SpellApiToAi.Converter.get(ApiType.Attach).canPlayWithSubs(ai, equip);
        AssertJUnit.assertTrue("AI should equip Skullclamp", d.willingToPlay());
        AssertJUnit.assertEquals("onto the 1/1 token to draw two", token, equip.getTargetCard());
    }

    // ---------------- Broadside Bombardiers ----------------

    private SpellAbility boast(Card bombardiers, Player ai) {
        SpellAbility sa = bombardiers.getSpellAbilities().stream()
                .filter(s -> s.getApi() == ApiType.DealDamage).findFirst().orElseThrow();
        sa.setActivatingPlayer(ai);
        return sa;
    }

    @Test
    public void testBombardiersGoesFaceWhenLethal() {
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        Player opp = game.getPlayers().get(0);
        opp.setLife(4, null);
        Card bombardiers = addCard("Broadside Bombardiers", ai);
        addToken("w_1_1_citizen", ai);              // 2 damage: not enough
        Card bears = addCard("Grizzly Bears", ai);   // 2 + 2 = 4: lethal
        game.getAction().checkStateEffects(true);

        SpellAbility sa = boast(bombardiers, ai);
        AssertJUnit.assertTrue(SpecialCardAi.BroadsideBombardiers.consider(ai, sa).willingToPlay());
        AssertJUnit.assertEquals(opp, sa.getTargets().getFirstTargetedPlayer());
        AssertJUnit.assertEquals(bears, ComputerUtil.getPlannedSacrifice(bombardiers));
    }

    @Test
    public void testBombardiersTradesTokenForBiggerCreature() {
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        Player opp = game.getPlayers().get(0);
        Card bombardiers = addCard("Broadside Bombardiers", ai);
        Card token = addToken("w_1_1_citizen", ai);   // 2 damage
        Card bigBlocker = addCard("Grizzly Bears", opp); // 2/2, worth more than a 1/1 token
        game.getAction().checkStateEffects(true);

        SpellAbility sa = boast(bombardiers, ai);
        AssertJUnit.assertTrue(SpecialCardAi.BroadsideBombardiers.consider(ai, sa).willingToPlay());
        AssertJUnit.assertEquals(bigBlocker, sa.getTargetCard());
        AssertJUnit.assertEquals(token, ComputerUtil.getPlannedSacrifice(bombardiers));
        // and the actual cost payment sacrifices that token
        CardCollection paid = ComputerUtil.chooseSacrificeType(ai, "Artifact.Other;Creature.Other", sa, null, false, 1, null);
        AssertJUnit.assertEquals(token, paid.getFirst());
    }

    @Test
    public void testBombardiersNeverSacrificesManaRockForATrade() {
        Game game = initAndCreateGame();
        Player ai = game.getPlayers().get(1);
        Player opp = game.getPlayers().get(0);
        Card bombardiers = addCard("Broadside Bombardiers", ai);
        addCard("Sol Ring", ai);
        addCard("Grizzly Bears", opp);
        game.getAction().checkStateEffects(true);

        AssertJUnit.assertFalse(SpecialCardAi.BroadsideBombardiers.consider(ai, boast(bombardiers, ai)).willingToPlay());
    }
}
