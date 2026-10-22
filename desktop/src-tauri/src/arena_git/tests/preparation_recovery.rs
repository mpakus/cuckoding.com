use super::*;

#[test]
fn retained_preparation_reads_only_exact_complete_evidence() {
    for scenario in [
        "valid",
        "missing_receipt",
        "missing_binding",
        "receipt_link",
        "binding_link",
        "receipt",
        "binding",
        "owner",
        "foreign_battle",
        "foreign_key",
        "extra_fields",
        "checkout",
        "source",
        "cancelled",
        "deadline",
    ] {
        let (root, home, request, baseline) = inspection_fixture();
        let args = &request[..5];
        let battle = initial(
            args,
            "create_battle",
            json!({"key":BATTLE_KEY,"head":baseline["head"]}),
        )
        .unwrap();
        let key = "00000000-0000-4000-8000-000000000171";
        let mut original = json!({"key":key,"battle":battle});
        let prepared = initial(args, "battle_worktree", original.clone()).unwrap();
        let checkout = Path::new(prepared["path"].as_str().unwrap());
        let directory = checkout.parent().unwrap();
        match scenario {
            "missing_receipt" => fs::remove_file(directory.join("receipt.json")).unwrap(),
            "missing_binding" => fs::remove_file(directory.join("battle.json")).unwrap(),
            "receipt_link" | "binding_link" => {
                let name = if scenario == "receipt_link" {
                    "receipt.json"
                } else {
                    "battle.json"
                };
                fs::copy(directory.join(name), directory.join("same-bytes.json")).unwrap();
                fs::remove_file(directory.join(name)).unwrap();
                std::os::unix::fs::symlink("same-bytes.json", directory.join(name)).unwrap();
            }
            "receipt" => fs::write(directory.join("receipt.json"), "{}").unwrap(),
            "binding" => fs::write(directory.join("battle.json"), "{}").unwrap(),
            "owner" => fs::write(directory.join("owner.json"), "{}").unwrap(),
            "foreign_battle" => {
                original["battle"]["battle_key"] = json!("00000000-0000-4000-8000-000000000172")
            }
            "foreign_key" => original["key"] = baseline["key"].clone(),
            "extra_fields" => original["candidate"] = json!({}),
            "checkout" => fs::write(checkout.join("docs/plan.txt"), "RETAIN_OWNED_EDIT").unwrap(),
            "source" => {
                fs::write(root.join("new.txt"), "new committed source").unwrap();
                commit_fixture(&root, &home);
            }
            _ => (),
        }
        fs::write(root.join("docs/plan.txt"), "USER_WORKING").unwrap();
        fs::write(root.join("untracked.txt"), "UNTRACKED_CANARY").unwrap();
        let source_index = fs::read(root.join(".git/index")).unwrap();
        let source_head = fs::read(root.join(".git/HEAD")).unwrap();
        let reference = root.join(format!(".git/{}", battle["reference"].as_str().unwrap()));
        let before_ref = fs::read(&reference).unwrap();
        let retained = ["owner.json", "receipt.json", "battle.json"]
            .map(|name| fs::read(directory.join(name)).ok());
        let owned_text = fs::read(checkout.join("docs/plan.txt")).unwrap();
        let result = if ["cancelled", "deadline"].contains(&scenario) {
            let mut command = args.to_vec();
            command[0] = "recover_battle_worktree".into();
            command.push(original.to_string());
            let (sender, receiver) = mpsc::channel();
            if scenario == "cancelled" {
                sender.send(()).unwrap();
            }
            run(
                &command,
                receiver,
                if scenario == "deadline" {
                    Duration::ZERO
                } else {
                    Duration::from_secs(15)
                },
            )
        } else {
            initial(args, "recover_battle_worktree", original.clone())
        };
        if scenario == "valid" {
            assert_eq!(result, Ok(prepared.clone()));
            assert_eq!(
                initial(args, "recover_battle_worktree", original),
                Ok(prepared.clone())
            );
        } else {
            assert!(result.is_err(), "{scenario}: {result:?}");
        }
        assert_eq!(
            ["owner.json", "receipt.json", "battle.json"]
                .map(|name| fs::read(directory.join(name)).ok()),
            retained
        );
        assert_eq!(
            fs::read(checkout.join("docs/plan.txt")).unwrap(),
            owned_text
        );
        assert_eq!(fs::read(root.join(".git/index")).unwrap(), source_index);
        assert_eq!(fs::read(root.join(".git/HEAD")).unwrap(), source_head);
        assert_eq!(fs::read(&reference).unwrap(), before_ref);
        assert_eq!(
            fs::read(root.join("docs/plan.txt")).unwrap(),
            b"USER_WORKING"
        );
        assert_eq!(
            fs::read(root.join("untracked.txt")).unwrap(),
            b"UNTRACKED_CANARY"
        );
        fs::remove_dir_all(root.parent().unwrap()).unwrap();
    }
}
