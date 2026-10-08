install.packages("usethis")
usethis::use_git_config(user.name = "Austin Foster",
                        user.email = "austin.thomas.fit@gmail.com")

usethis::create_github_token()
gitcreds::gitcreds_set()   # paste the token when prompted
usethis::git_sitrep()
usethis::git_sitrep(scope = "user")
