pipeline
{
    agent any

    stages
    {
        stage( 'CA Integration Test' )
        {
            agent { dockerfile true }
            steps
            {
                sh 'ls -lah'
                sh 'echo replace_me_with_a_docker_run'
            }
        }

        stage( 'Build and Push to Dockerhub' )
        {
            steps
            {
                script
                {
                    docker.withRegistry('', 'safe.docker.login.id')
                    {
                        def customImage = docker.build( "devops4me/cert-authority" )
                        customImage.push( "v1.0.0" )
                        customImage.push( "latest" )
                    }
                }
            }
        }
    }
}
